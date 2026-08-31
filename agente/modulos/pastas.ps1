<#
================================================================================
  CH.Com Cofre - pastas escolhidas a mao

  Nem todo dado de cartorio esta dentro de VM ou de banco. Ha a pasta dos
  documentos digitalizados, a pasta que o sistema usa para anexos, a pasta
  compartilhada onde o pessoal trabalha. Isso precisa ir para o Cofre igual.

  O PROBLEMA: ARQUIVO ABERTO

  Copiar uma pasta enquanto o cartorio trabalha nela significa que alguns
  arquivos estarao abertos - e o Windows recusa a leitura. Copiar assim
  deixaria de fora justamente os arquivos em uso, que sao os mais recentes.

  A SOLUCAO: COPIA DE SOMBRA (VSS)

  O Cofre pede ao Windows uma copia de sombra do volume - um retrato
  congelado do disco naquele instante - e copia DE LA. Arquivo aberto,
  arquivo travado, arquivo sendo gravado: todos aparecem, no estado em que
  estavam no instante do retrato.

  E o mesmo mecanismo que o Export-VM usa por baixo. Nativo, gratuito, e a
  unica forma correta de copiar pasta de servidor em producao.

  Se o VSS falhar, o Cofre AVISA e copia assim mesmo, listando o que ficou de
  fora - em vez de fingir que copiou tudo.
================================================================================
#>

<#
    Cria a copia de sombra de um volume.

    Win32_ShadowCopy e a interface do proprio Windows, chamada por WMI. Nao
    precisa de ferramenta externa, nem do diskshadow, e funciona tanto em
    Server quanto em client.

    Devolve o caminho de dispositivo da sombra, algo como

        \?\GLOBALROOT\Device\HarddiskVolumeShadowCopy7

    que se le como se fosse uma pasta.
#>
function CriarSombra([string]$volume) {
    $r = [PSCustomObject]@{ Criada = $false; Id = $null; Dispositivo = $null; Erro = $null }

    try {
        # O volume precisa vir como "C:\" - com a barra. Sem ela o WMI aceita
        # a chamada e devolve erro generico, sem dizer o porque.
        $raizVolume = $volume.Substring(0, 2) + '\'

        $classe = [wmiclass]'root\cimv2:Win32_ShadowCopy'
        $resultado = $classe.Create($raizVolume, 'ClientAccessible')

        if ($resultado.ReturnValue -ne 0) {
            throw "o Windows recusou a copia de sombra (codigo $($resultado.ReturnValue))"
        }

        $sombra = Get-CimInstance Win32_ShadowCopy -Filter "ID='$($resultado.ShadowID)'"
        if (-not $sombra) { throw 'a copia de sombra foi criada mas nao foi encontrada' }

        $r.Id = $resultado.ShadowID
        # O DeviceObject nao termina com barra, e sem ela a concatenacao de
        # caminho junta o nome do dispositivo com a primeira pasta.
        $r.Dispositivo = $sombra.DeviceObject + '\'
        $r.Criada = $true

    } catch {
        $r.Erro = $_.Exception.Message
    }
    return $r
}

function RemoverSombra([string]$id) {
    if (-not $id) { return }
    try {
        $s = Get-CimInstance Win32_ShadowCopy -Filter "ID='$id'" -ErrorAction SilentlyContinue
        if ($s) { Remove-CimInstance -InputObject $s -ErrorAction SilentlyContinue }
    } catch { }
}

<#
    Copia uma pasta para a area de trabalho, passando pela copia de sombra.

    O robocopy faz a copia porque ele:
      - retoma de onde parou
      - copia atributos e datas
      - devolve um relatorio de quantos arquivos falharam
      - tem codigo de saida que distingue "copiou" de "copiou com problema"

    Codigos do robocopy: 0 a 7 sao sucesso (0 = nada mudou, 1 = copiou,
    2 = havia extras, 4 = arquivos diferentes...). 8 ou mais e falha de
    verdade. Tratar tudo diferente de zero como erro - que e o reflexo comum -
    faria toda copia bem sucedida parecer defeito.
#>
function CopiarPasta {
    param(
        [Parameter(Mandatory)] [string]$Origem,
        [Parameter(Mandatory)] [string]$Destino,
        [switch]$SemSombra
    )

    $r = [PSCustomObject]@{
        Origem = $Origem; Destino = $Destino; Sucesso = $false
        UsouSombra = $false; Arquivos = 0; TamanhoBytes = 0
        NaoCopiados = 0; Duracao = [TimeSpan]::Zero; Erro = $null; Aviso = $null
    }
    $relogio = [Diagnostics.Stopwatch]::StartNew()
    $sombra = $null

    try {
        if (-not (Test-Path $Origem)) { throw "a pasta nao existe: $Origem" }
        if (-not (Test-Path $Destino)) { New-Item -ItemType Directory -Path $Destino -Force | Out-Null }

        $deOnde = $Origem

        if (-not $SemSombra) {
            $sombra = CriarSombra $Origem
            if ($sombra.Criada) {
                # Troca "C:\pasta\sub" por "<dispositivo da sombra>\pasta\sub"
                $resto = $Origem.Substring(3)
                $deOnde = $sombra.Dispositivo + $resto
                $r.UsouSombra = $true
            } else {
                $r.Aviso = "sem copia de sombra ($($sombra.Erro)). Arquivos abertos podem ficar de fora."
            }
        }

        # /E   subpastas, inclusive vazias
        # /COPY:DAT  dados, atributos e datas (nao copia dono nem permissao:
        #            isso viaja mal entre servidores e o que importa aqui e o
        #            conteudo)
        # /R:2 /W:5  duas tentativas, cinco segundos - um arquivo travado nao
        #            pode segurar a copia por meia hora
        # /NFL /NDL  sem listar cada arquivo: o log viraria centenas de MB
        # /NP        sem porcentagem, que polui o registro
        $exec = RodarPrograma -Programa 'robocopy' -Argumentos @(
            $deOnde, $Destino, '/E', '/COPY:DAT', '/R:2', '/W:5', '/NFL', '/NDL', '/NP')
        $codigo = $exec.Codigo
        $texto = ((LinhasLimpas $exec.Tudo) -join [Environment]::NewLine)

        <#
            O codigo do robocopy nao e "zero deu certo".

            0 a 7 = sucesso (0 nada mudou, 1 copiou, 2 havia extras, 4 tinha
            arquivo diferente, e as somas disso).
            8 ou mais = ALGUM arquivo falhou.

            E "algum arquivo falhou" NAO e a mesma coisa que "a copia
            falhou". Conferido em teste: com um arquivo travado no meio de
            tres, o robocopy devolve 9 e mesmo assim copia os outros dois.

            A primeira versao lancava excecao no codigo 9 - e jogava fora a
            copia inteira por causa de um arquivo, alem de perder a contagem
            do que tinha chegado. Agora a copia vale, e o que faltou aparece
            no relatorio com nome e numero.
        #>
        foreach ($f in @(Get-ChildItem $Destino -Recurse -File -ErrorAction SilentlyContinue)) {
            $r.Arquivos++
            $r.TamanhoBytes += $f.Length
        }

        # A linha de resumo traz: total, copiados, ignorados, incompativeis,
        # FALHAS, extras. O quinto numero e o que interessa.
        if ($texto -match '(?m)^\s*(?:Arquivos|Files)\s*:\s*\d+\s+\d+\s+\d+\s+\d+\s+(\d+)') {
            $r.NaoCopiados = [int]$Matches[1]
        }

        if ($r.Arquivos -eq 0) {
            throw "nada foi copiado (robocopy codigo $codigo)"
        }

        if ($codigo -ge 8 -or $r.NaoCopiados -gt 0) {
            $quantos = if ($r.NaoCopiados -gt 0) { $r.NaoCopiados } else { 'alguns' }
            $porque = if ($r.UsouSombra) {
                'Mesmo com copia de sombra - pode ser permissao ou caminho longo demais.'
            } else {
                'Sem copia de sombra, arquivo aberto nao pode ser lido. Rode como Administrador.'
            }
            $r.Aviso = "$quantos arquivo(s) NAO foram copiados. $porque"
        }

        $r.Sucesso = $true

    } catch {
        $r.Erro = $_.Exception.Message
    } finally {
        if ($sombra -and $sombra.Criada) { RemoverSombra $sombra.Id }
        $relogio.Stop(); $r.Duracao = $relogio.Elapsed
    }
    return $r
}
