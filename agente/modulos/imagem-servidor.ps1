<#
================================================================================
  CH.Com Cofre - imagem do servidor fisico

  Para o cartorio que NAO tem Hyper-V.

  Nem todo cartorio virtualiza. Muitos tem um servidor fisico com o sistema e
  o banco rodando direto no Windows. Para esses, exportar VM nao existe - e
  copiar so os arquivos deixaria o cliente sem a maquina.

  A FERRAMENTA: wbadmin, do proprio Windows Server

      wbadmin start backup -allCritical -backupTarget:<disco> -quiet

  Gera VHDX dos volumes criticos (sistema, boot, reservado) e grava o catalogo
  de recuperacao. Com isso da para:

    - recuperacao bare metal, pelo ambiente de recuperacao do Windows
      (wbadmin start sysrecovery), em hardware diferente
    - anexar o VHDX a uma maquina virtual e subir o servidor como VM em outro
      lugar enquanto o hardware nao volta - que costuma ser o que salva o
      cartorio no dia seguinte ao incendio

  Nativo, gratuito, suportado pela Microsoft. Sem agente e sem licenca.

  O QUE NAO SERVE

  Windows client (10/11). O comando existe, mas o recurso de imagem de sistema
  foi marcado como obsoleto pela Microsoft e nao recebe correcao. O Cofre
  recusa usar isso como base de recuperacao de um servidor de cartorio, e diz
  o porque em vez de fingir que protegeu.
================================================================================
#>

<#
    Tira a imagem.

    -allCritical  todos os volumes necessarios para a maquina voltar
    -quiet        sem perguntar nada: isto roda de madrugada, sem ninguem
    -vssFull      informa aos writers que este e um backup completo, para
                  eles marcarem os logs como copiados

    Sobre o -vssFull: NAO e usado aqui, de proposito. Ele faz o SQL Server
    truncar o log de transacoes, o que estragaria a rotina de backup local que
    o cartorio ja tem. O Cofre e copia EXTRA para desastre - nao pode mexer no
    que ja funciona. Por padrao o wbadmin faz copia de backup (vssCopy), que
    nao mexe nos logs de ninguem.
#>
function ImagemDoServidor {
    param(
        [Parameter(Mandatory)] [string]$Destino,   # unidade ou pasta de rede
        [switch]$IncluirEstadoDoSistema
    )

    $r = [PSCustomObject]@{
        Destino = $Destino; Sucesso = $false; Pasta = $null
        TamanhoBytes = 0; Duracao = [TimeSpan]::Zero; Erro = $null; Saida = ''
    }
    $relogio = [Diagnostics.Stopwatch]::StartNew()

    try {
        $wb = (Get-Command wbadmin.exe -ErrorAction Stop).Source

        $argumentos = @('start', 'backup', "-backupTarget:$Destino", '-allCritical', '-quiet')
        if ($IncluirEstadoDoSistema) { $argumentos += '-systemState' }

        $saida = & $wb @argumentos 2>&1
        $r.Saida = ($saida | Out-String).Trim()

        if ($LASTEXITCODE -ne 0) {
            throw "wbadmin terminou com codigo $LASTEXITCODE. $($r.Saida)"
        }

        # O wbadmin cria "WindowsImageBackup\<NOME-DA-MAQUINA>" no destino.
        $pasta = CaminhoDe (CaminhoDe $Destino 'WindowsImageBackup') $env:COMPUTERNAME
        if (-not (Test-Path $pasta)) {
            throw "o wbadmin terminou sem erro, mas nao achei a pasta da imagem em $pasta"
        }

        $r.Pasta = $pasta
        foreach ($f in @(Get-ChildItem $pasta -Recurse -File -ErrorAction SilentlyContinue)) {
            $r.TamanhoBytes += $f.Length
        }
        if ($r.TamanhoBytes -eq 0) { throw 'a pasta da imagem esta vazia' }

        $r.Sucesso = $true

    } catch {
        $r.Erro = $_.Exception.Message
    } finally {
        $relogio.Stop(); $r.Duracao = $relogio.Elapsed
    }
    return $r
}

<#
    Confere a imagem gerada.

    O wbadmin nao tem um "verificar" proprio. O que da para conferir sem
    restaurar:

      1. o catalogo lista a versao que acabou de ser criada
      2. os VHDX abrem - montar e desmontar prova que o cabecalho e a tabela
         de blocos estao integros, que e onde a corrupcao costuma aparecer

    Montar exige privilegio de administrador. Quando nao houver, a conferencia
    diz que nao pode ser feita, em vez de dizer que passou.
#>
function ConferirImagem {
    param([Parameter(Mandatory)] [string]$PastaDaImagem)

    $r = [PSCustomObject]@{ Integra = $false; Discos = 0; Erro = $null; Ressalvas = @() }

    try {
        $vhds = @(Get-ChildItem $PastaDaImagem -Recurse -File -ErrorAction Stop |
                  Where-Object { $_.Extension -in @('.vhdx', '.vhd') })

        if ($vhds.Count -eq 0) { throw 'nao ha nenhum VHDX dentro da pasta da imagem' }
        $r.Discos = $vhds.Count

        if (-not (EhAdministrador)) {
            $r.Ressalvas += 'sem privilegio de administrador: nao deu para abrir os discos para conferir'
            $r.Integra = $true   # o que deu para conferir, conferiu
            return $r
        }

        foreach ($v in $vhds) {
            $montado = $null
            try {
                # Somente leitura e sem letra de unidade: so queremos saber se
                # o arquivo abre, nao mexer no conteudo.
                $montado = Mount-DiskImage -ImagePath $v.FullName -Access ReadOnly -NoDriveLetter -PassThru -ErrorAction Stop
            } catch {
                throw "o disco $($v.Name) nao abriu: $($_.Exception.Message)"
            } finally {
                if ($montado) {
                    Dismount-DiskImage -ImagePath $v.FullName -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }
        $r.Integra = $true

    } catch {
        $r.Erro = $_.Exception.Message
    }
    return $r
}
