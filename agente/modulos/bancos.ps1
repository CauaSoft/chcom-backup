<#
================================================================================
  CH.Com Cofre - backup de bancos de dados

  A REGRA DESTE ARQUIVO: NUNCA COPIAR ARQUIVO DE BANCO ABERTO.

  Copiar um .fdb ou um .mdf enquanto o banco esta rodando produz um arquivo
  que as vezes abre e as vezes nao - e ninguem descobre qual dos dois ate
  precisar. Nao existe "deu certo das outras vezes": e sorte, medida no pior
  momento possivel.

  FIREBIRD

  Nao tem VSS Writer. Nenhum. Nem o snapshot do Windows salva - o Firebird
  nao e avisado de nada e continua escrevendo durante a copia. A unica forma
  suportada pelo fabricante e o gbak, que le pelo motor do banco e produz um
  .fbk consistente com a VM ligada e os usuarios trabalhando.

  SQL SERVER

  Tem VSS Writer, entao uma imagem de volume PODE sair consistente. Mesmo
  assim o Cofre faz BACKUP DATABASE, por duas coisas que imagem nao resolve:

    - restaurar UMA base sem restaurar a maquina inteira
    - ponto no tempo, com os logs

  Num desastre voce quer as duas.
================================================================================
#>

<#
    Firebird via gbak.

    -b        modo backup
    -g        nao coleta lixo durante o backup: mais rapido e nao mexe no
              banco de producao mais do que o necessario
    -v        verboso, para o log ter o que mostrar quando falhar
    -user/-pass  credenciais do SYSDBA

    A SENHA NAO VAI PELA LINHA DE COMANDO.

    Qualquer programa da maquina le a lista de processos e ve os argumentos.
    O gbak aceita as variaveis ISC_USER e ISC_PASSWORD, que ficam so no
    ambiente deste processo e somem quando ele termina.
#>
function BackupFirebird {
    param(
        [Parameter(Mandatory)] [string]$Gbak,
        [Parameter(Mandatory)] [string]$Banco,        # caminho do .fdb ou alias
        [Parameter(Mandatory)] [string]$Destino,      # arquivo .fbk a criar
        [string]$Usuario = 'SYSDBA',
        [string]$Senha = ''
    )

    $r = [PSCustomObject]@{
        Banco = $Banco; Arquivo = $Destino; Sucesso = $false
        TamanhoBytes = 0; Duracao = [TimeSpan]::Zero; Erro = $null; Saida = ''
    }
    $relogio = [Diagnostics.Stopwatch]::StartNew()

    try {
        $pasta = Split-Path $Destino -Parent
        if (-not (Test-Path $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
        if (Test-Path $Destino) { Remove-Item $Destino -Force }

        $env:ISC_USER = $Usuario
        if ($Senha) { $env:ISC_PASSWORD = $Senha }

        <#
            O gbak -v fala enquanto trabalha, e fala pelo stderr.

            Com 2>&1 dentro de um script com ErrorActionPreference = Stop,
            a PRIMEIRA linha de "lendo tabela CLIENTES" virava erro terminante
            e o backup do banco morria - com o gbak trabalhando direito e
            terminando com codigo 0.
        #>
        $exec = RodarPrograma -Programa $Gbak -Argumentos @('-b', '-g', '-v', $Banco, $Destino)
        $r.Saida = ((LinhasLimpas $exec.Tudo) -join [Environment]::NewLine)

        if ($exec.Codigo -ne 0) {
            $motivo = (LinhasLimpas $exec.Erro | Select-Object -First 2) -join ' | '
            if (-not $motivo) { $motivo = "codigo $($exec.Codigo)" }
            throw "o gbak nao conseguiu ler o banco: $motivo"
        }
        if (-not (Test-Path $Destino)) {
            throw 'o gbak nao reclamou, mas o arquivo .fbk nao foi criado'
        }

        $r.TamanhoBytes = (Get-Item $Destino).Length
        if ($r.TamanhoBytes -eq 0) { throw 'o .fbk saiu com zero bytes' }
        $r.Sucesso = $true

    } catch {
        $r.Erro = $_.Exception.Message
    } finally {
        # A senha some do ambiente aconteca o que acontecer.
        Remove-Item Env:\ISC_PASSWORD -ErrorAction SilentlyContinue
        Remove-Item Env:\ISC_USER -ErrorAction SilentlyContinue
        $relogio.Stop(); $r.Duracao = $relogio.Elapsed
    }
    return $r
}

<#
    Confere que o .fbk restaura de verdade.

    gbak -c restaura para um banco novo. O Cofre faz isso num arquivo
    temporario, confirma que abriu, e apaga.

    Isto e o que separa "gerei um arquivo" de "tenho um backup". Um .fbk
    truncado tem tamanho, tem data, e nao restaura - e sem esta conferencia
    ele subiria para a AWS com cara de backup bom.
#>
function ConferirFirebird {
    param(
        [Parameter(Mandatory)] [string]$Gbak,
        [Parameter(Mandatory)] [string]$Arquivo,
        [string]$Usuario = 'SYSDBA',
        [string]$Senha = ''
    )

    $r = [PSCustomObject]@{ Restaura = $false; Erro = $null }
    $teste = CaminhoDe $env:TEMP ('cofre-teste-' + [Guid]::NewGuid().ToString('N') + '.fdb')

    try {
        $env:ISC_USER = $Usuario
        if ($Senha) { $env:ISC_PASSWORD = $Senha }

        $exec = RodarPrograma -Programa $Gbak -Argumentos @('-c', '-v', $Arquivo, $teste)
        if ($exec.Codigo -ne 0) {
            $motivo = (LinhasLimpas $exec.Erro | Select-Object -First 2) -join ' | '
            if (-not $motivo) { $motivo = "codigo $($exec.Codigo)" }
            throw "a restauracao de teste falhou: $motivo"
        }
        if (-not (Test-Path $teste)) { throw 'a restauracao de teste nao gerou banco' }
        $r.Restaura = $true

    } catch {
        $r.Erro = $_.Exception.Message
    } finally {
        Remove-Item Env:\ISC_PASSWORD -ErrorAction SilentlyContinue
        Remove-Item Env:\ISC_USER -ErrorAction SilentlyContinue
        Remove-Item $teste -Force -ErrorAction SilentlyContinue
    }
    return $r
}

<#
    SQL Server: backup nativo de todas as bases da instancia.

    A conexao usa autenticacao do Windows. O Cofre roda como servico do
    sistema, e o SYSTEM local costuma ser sysadmin nas instalacoes de
    cartorio; quando nao for, o erro diz isso claramente em vez de falhar
    de forma obscura.

    Bases de sistema:
      master, msdb  - vao. Guardam logins, jobs e agendamentos, e sem elas o
                      servidor restaurado nao e o mesmo servidor.
      model         - vai, e minuscula.
      tempdb        - NAO vai. E recriada toda vez que o SQL Server sobe;
                      fazer backup dela nem e permitido.
#>
function BackupSqlServer {
    param(
        [Parameter(Mandatory)] [string]$Instancia,
        [Parameter(Mandatory)] [string]$PastaDestino
    )

    $r = [PSCustomObject]@{
        Instancia = $Instancia; Bases = @(); Sucesso = $false
        TamanhoBytes = 0; Duracao = [TimeSpan]::Zero; Erro = $null
    }
    $relogio = [Diagnostics.Stopwatch]::StartNew()

    try {
        if (-not (Test-Path $PastaDestino)) {
            New-Item -ItemType Directory -Path $PastaDestino -Force | Out-Null
        }

        $bases = @(ConsultarSql $Instancia
            "SELECT name FROM sys.databases WHERE name <> 'tempdb' AND state = 0 ORDER BY name")

        if ($bases.Count -eq 0) { throw 'nenhuma base encontrada na instancia' }

        foreach ($linha in $bases) {
            $nome = $linha.name
            $arq = CaminhoDe $PastaDestino ("$nome.bak")
            $item = [PSCustomObject]@{ Base = $nome; Arquivo = $arq; Sucesso = $false; Integro = $false; Erro = $null; Bytes = 0 }

            try {
                if (Test-Path $arq) { Remove-Item $arq -Force }

                # COPY_ONLY: nao quebra a cadeia de backup que o cartorio ja
                # tenha. O Cofre e copia EXTRA para desastre; se ele marcasse
                # o log como copiado, estragaria a rotina local de quem ja faz
                # backup diferencial - e isso seria fazer estrago no cliente.
                $sql = "BACKUP DATABASE [$nome] TO DISK = N'$arq' WITH COPY_ONLY, INIT, COMPRESSION, CHECKSUM, STATS = 100"
                ExecutarSql $Instancia $sql

                # RESTORE VERIFYONLY nao restaura: le o arquivo inteiro e
                # confere os checksums. E o mais perto de "isto restaura" que
                # da para afirmar sem derrubar o banco.
                ExecutarSql $Instancia "RESTORE VERIFYONLY FROM DISK = N'$arq' WITH CHECKSUM"
                $item.Integro = $true

                $item.Bytes = (Get-Item $arq).Length
                $item.Sucesso = $true
                $r.TamanhoBytes += $item.Bytes

            } catch {
                $item.Erro = $_.Exception.Message
            }
            $r.Bases += $item
        }

        $r.Sucesso = (@($r.Bases | Where-Object { -not $_.Sucesso }).Count -eq 0)
        if (-not $r.Sucesso) {
            $falhas = @($r.Bases | Where-Object { -not $_.Sucesso } | ForEach-Object { $_.Base })
            $r.Erro = "falharam: $($falhas -join ', ')"
        }

    } catch {
        $r.Erro = $_.Exception.Message
    } finally {
        $relogio.Stop(); $r.Duracao = $relogio.Elapsed
    }
    return $r
}

<#
    Conversa com o SQL Server sem depender do modulo SqlServer.

    O modulo oficial exige instalacao pela galeria, que num servidor de
    cartorio sem internet liberada simplesmente nao acontece. System.Data.
    SqlClient vem no .NET Framework, que ja esta em toda maquina Windows.
#>
function ConexaoSql([string]$instancia) {
    $c = New-Object System.Data.SqlClient.SqlConnection
    $c.ConnectionString = "Server=$instancia;Integrated Security=True;Connect Timeout=15;Application Name=CH.Com Cofre"
    $c.Open()
    return $c
}

function ExecutarSql([string]$instancia, [string]$sql) {
    $con = $null
    try {
        $con = ConexaoSql $instancia
        $cmd = $con.CreateCommand()
        $cmd.CommandText = $sql
        # Backup de base grande passa facil de 30 segundos, que e o padrao.
        # Zero = sem limite: quem decide quando desistir e o operador.
        $cmd.CommandTimeout = 0
        [void]$cmd.ExecuteNonQuery()
    } finally {
        if ($con) { $con.Close() }
    }
}

function ConsultarSql([string]$instancia, [string]$sql) {
    $con = $null
    try {
        $con = ConexaoSql $instancia
        $cmd = $con.CreateCommand()
        $cmd.CommandText = $sql
        $cmd.CommandTimeout = 60
        $leitor = $cmd.ExecuteReader()
        $tabela = New-Object System.Data.DataTable
        $tabela.Load($leitor)
        return @($tabela.Rows)
    } finally {
        if ($con) { $con.Close() }
    }
}
