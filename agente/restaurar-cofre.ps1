<#
================================================================================
  CH.Com Cofre - restaurar

  A UNICA PARTE DO SISTEMA QUE IMPORTA DE VERDADE.

  Todo o resto existe para que esta operacao funcione no pior dia do cartorio.

  COMO FUNCIONA A RECUPERACAO DO DEEP ARCHIVE

  Os dados ficam no S3 Glacier Deep Archive, que custa cerca de 1 dolar por
  terabyte por mes justamente porque NAO E IMEDIATO. Ler exige tres etapas:

    1. PEDIR o descongelamento (restore) dos objetos
    2. ESPERAR - 12 horas no modo padrao, ate 48 horas no modo economico
    3. BAIXAR, decifrar e conferir

  Nao ha como acelerar. Quem promete restauracao imediata de Deep Archive esta
  enganando alguem.

  O QUE ESTE PROGRAMA FAZ DE DIFERENTE

  Ele confere o que voltou contra as impressoes digitais SHA-256 gravadas no
  dia do backup. Sem isso, "baixei os arquivos" e so uma esperanca.

  USO
      restaurar-cofre.ps1 -Listar
      restaurar-cofre.ps1 -Descongelar <caminho> [-Rapido]
      restaurar-cofre.ps1 -Situacao <caminho>
      restaurar-cofre.ps1 -Baixar <caminho> -Para <pasta>
================================================================================
#>

[CmdletBinding()]
param(
    [switch]$Listar,
    [string]$Descongelar,
    [string]$Situacao,
    [string]$Baixar,
    [string]$Para,
    # Modo rapido: 12 h e cerca de 8x mais caro. O economico leva ate 48 h.
    [switch]$Rapido
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($m in @('comum','validar','enviar','configurar')) {
    . (Join-Path $raiz "modulos\$m.ps1")

# Onde ficam configuracao, estado e historico. NAO e a pasta do codigo:
# Program Files e somente leitura para quem nao e administrador.
$dados = PastaDeDados $raiz
}

DesligarCliqueQueTrava
Marca

$config = LerConfiguracao (CaminhoDe $dados 'cofre.conf')
if (-not $config) { Erro 'este servidor nao esta configurado.'; exit 1 }

$rclone = CaminhoDoRclone $raiz
if (-not $rclone) { Erro 'o rclone nao esta nesta pasta.'; exit 1 }
$conf = CaminhoDe $dados 'rclone.conf'
$remoto = $config.Remoto

# ------------------------------------------------------------------------------
#  Listar o que existe na nuvem
#
#  A listagem le METADADOS, que continuam acessiveis mesmo com o conteudo
#  congelado. Da para ver tudo que existe sem gastar um centavo de resgate.
# ------------------------------------------------------------------------------
if ($Listar) {
    Titulo 'O que existe no Cofre'
    $exec = RodarRclone -Rclone $rclone -Argumentos @(
        'lsjson', "${remoto}:$($config.Cartorio)", '--config', $conf, '--recursive', '--dirs-only')
    if ($exec.Codigo -ne 0) { Erro "nao consegui listar: $($exec.Erro)"; exit 1 }

    $itens = LerListaDoRclone $exec.Saida
    # So as pastas de data, que sao os pontos de recuperacao. As de cima sao
    # cartorio, maquina, tipo e nome - estrutura, nao ponto de recuperacao.
    $pontos = @($itens | Where-Object { $_.Path -match '\d{4}-\d{2}-\d{2}$' } |
                Sort-Object Path -Descending)

    if ($pontos.Count -eq 0) { Aviso 'nao ha nenhum ponto de recuperacao no Cofre.'; exit 0 }

    Write-Host ''
    foreach ($p in $pontos) {
        Write-Host ("    {0}" -f $p.Path) -ForegroundColor Gray
    }
    Write-Host ''
    Nota "$($pontos.Count) ponto(s) de recuperacao."
    Nota 'Para recuperar um deles:'
    Nota '  restaurar-cofre.ps1 -Descongelar "<caminho acima>"'
    exit 0
}

# ------------------------------------------------------------------------------
#  Pedir o descongelamento
#
#  O rclone nao tem comando de restore do Glacier. Quem faz e a AWS, pelo
#  proprio S3 - e o rclone sabe chamar isso com "backend restore".
#
#  Prioridade:
#    Standard  ate 12 h, cerca de 0,02 USD por GB
#    Bulk      ate 48 h, cerca de 0,0025 USD por GB
#
#  O padrao aqui e Bulk. Recuperacao de desastre e planejada, nao urgente ao
#  ponto de pagar 8x mais - e quando for urgente, existe o -Rapido.
# ------------------------------------------------------------------------------
if ($Descongelar) {
    $prioridade = if ($Rapido) { 'Standard' } else { 'Bulk' }
    $prazo = if ($Rapido) { 'ate 12 horas' } else { 'ate 48 horas' }

    Titulo "Pedindo o descongelamento"
    Nota "caminho    : $Descongelar"
    Nota "modo       : $prioridade ($prazo)"
    Nota "custo      : $(if ($Rapido) { 'cerca de 0,02 USD por GB' } else { 'cerca de 0,0025 USD por GB' })"
    Write-Host ''

    $saida = & $rclone backend restore "${remoto}:$Descongelar" `
        --config $conf -o priority=$prioridade -o lifetime=7 2>&1

    if ($LASTEXITCODE -ne 0) {
        Erro "o pedido falhou: $(($saida | Out-String).Trim())"
        exit 1
    }

    Ok 'pedido enviado a AWS'
    Write-Host ''
    Nota "Os arquivos ficam disponiveis por 7 dias depois de descongelados."
    Nota "Acompanhe com:"
    Nota "  restaurar-cofre.ps1 -Situacao `"$Descongelar`""
    Nota 'Nao adianta tentar baixar antes: a AWS recusa objeto ainda congelado.'
    exit 0
}

# ------------------------------------------------------------------------------
#  Ver se ja descongelou
# ------------------------------------------------------------------------------
if ($Situacao) {
    Titulo 'Situacao do descongelamento'

    $exec = RodarRclone -Rclone $rclone -Argumentos @(
        'backend', 'restore-status', "${remoto}:$Situacao", '--config', $conf)
    if ($exec.Codigo -ne 0) { Erro "nao consegui consultar: $($exec.Erro)"; exit 1 }

    $texto = ($exec.Saida | Out-String)
    Write-Host $texto -ForegroundColor Gray

    # O rclone devolve o estado por objeto. "ongoing-request true" significa
    # que a AWS ainda esta trabalhando naquele arquivo.
    if ($texto -match 'ongoing-request.{0,10}true') {
        Aviso 'ainda descongelando. Volte a consultar mais tarde.'
    } elseif ($texto -match 'expiry-date') {
        Ok 'descongelado e pronto para baixar.'
        Nota "  restaurar-cofre.ps1 -Baixar `"$Situacao`" -Para D:\recuperado"
    } else {
        Nota 'sem informacao de descongelamento - pode ja estar acessivel.'
    }
    exit 0
}

# ------------------------------------------------------------------------------
#  Baixar, decifrar e CONFERIR
# ------------------------------------------------------------------------------
if ($Baixar) {
    if (-not $Para) { Erro 'falta dizer para onde baixar, com -Para'; exit 1 }

    Titulo 'Trazendo do Cofre'
    Nota "de   : $Baixar"
    Nota "para : $Para"
    Write-Host ''

    if (-not (Test-Path $Para)) { New-Item -ItemType Directory -Path $Para -Force | Out-Null }

    Passo 'baixando e decifrando...'
    $saida = & $rclone copy "${remoto}:$Baixar" $Para --config $conf `
        --transfers 4 --retries 10 --low-level-retries 20 --stats 10s --stats-one-line 2>&1

    if ($LASTEXITCODE -ne 0) {
        Erro "a copia falhou: $(($saida | Out-String).Trim())"
        Nota 'Se a mensagem falar em objeto arquivado, o descongelamento ainda nao terminou.'
        exit 1
    }
    Ok 'arquivos trazidos'

    <#
        A conferencia.

        Aqui e onde "baixei os arquivos" vira "o backup esta integro". Cada
        arquivo e comparado com o SHA-256 gravado no dia do backup, antes de
        ele sair do cartorio.

        Se isto passar, o que esta no disco e byte por byte o que foi
        protegido - nao uma aproximacao, nao uma esperanca.
    #>
    $manifesto = CaminhoDe $Para 'cofre-manifesto.json'
    if (-not (Test-Path $manifesto)) {
        Aviso 'nao ha manifesto nesta copia - nao da para conferir as impressoes digitais.'
        Nota 'Os arquivos estao ai, mas ninguem pode afirmar que estao integros.'
        exit 0
    }

    Write-Host ''
    Passo 'conferindo cada arquivo contra a impressao digital...'
    $r = ConferirContraManifesto -Pasta $Para -ArquivoManifesto $manifesto

    Write-Host ''
    if ($r.Divergentes.Count -eq 0 -and $r.Faltando.Count -eq 0) {
        Caixa @('RECUPERACAO CONFERIDA',
                '',
                "$($r.Conferidos) arquivo(s) conferidos, byte por byte.",
                'O que esta no disco e exatamente o que foi protegido.') 'Green'
    } else {
        Caixa @('A CONFERENCIA NAO PASSOU',
                '',
                "$($r.Conferidos) conferidos, $($r.Divergentes.Count) diferentes, $($r.Faltando.Count) faltando.") 'Red'
        foreach ($d in $r.Divergentes) { Erro "diferente do original: $d" }
        foreach ($f in $r.Faltando)    { Erro "nao veio: $f" }
        Write-Host ''
        Nota 'Baixe de novo antes de confiar nestes arquivos.'
        exit 1
    }
    exit 0
}

# --- sem argumento ------------------------------------------------------------
Titulo 'Como usar'
Nota '  restaurar-cofre.ps1 -Listar'
Nota '  restaurar-cofre.ps1 -Descongelar "<caminho>"        (ate 48 h, barato)'
Nota '  restaurar-cofre.ps1 -Descongelar "<caminho>" -Rapido (ate 12 h, 8x mais caro)'
Nota '  restaurar-cofre.ps1 -Situacao "<caminho>"'
Nota '  restaurar-cofre.ps1 -Baixar "<caminho>" -Para D:\recuperado'
Write-Host ''
