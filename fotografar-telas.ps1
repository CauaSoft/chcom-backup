<#
================================================================================
  CH.Com Cofre - fotografar as telas

  Desenha cada tela num arquivo PNG, sem abrir janela nenhuma.

  POR QUE ISTO EXISTE

  Passei semanas mexendo no Painel sem NUNCA ter olhado para ele. O banco de
  provas dizia "montou 930x605px" e passava - e a tela, na foto, mostrava
  "ultima copia ha 9h, 88 GB enviados" ao lado de "0% protegido, 0 de 5
  itens". As duas coisas verdadeiras, juntas sem sentido nenhum.

  Nenhuma prova automatica pega isso. Olhar pega em dois segundos.

  USO
      powershell -ExecutionPolicy Bypass -File fotografar-telas.ps1
      (as fotos saem em dist\fotos)
================================================================================
#>

[CmdletBinding()]
param(
    [string]$Saida = '',
    [int]$Largura = 1400,
    [int]$Altura = 1000
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$raiz = $PSScriptRoot
if (-not $Saida) { $Saida = Join-Path $raiz 'dist\fotos' }
$agente = Join-Path $raiz 'agente'
$ui = Join-Path $agente 'interface'

if (-not (Test-Path $Saida)) { New-Item -ItemType Directory -Path $Saida -Force | Out-Null }

. (Join-Path $agente 'modulos\comum.ps1')
$dados = PastaDeDados $agente

<#
    Monta um servidor de mentira, mas plausivel.

    Volume que cai pela metade nos ultimos dias e uma falha no meio: e assim
    que um parque de verdade se parece, e e nesse estado que os defeitos de
    tela aparecem. Um cenario perfeito nao mostra nada.
#>
function MontarCenario {
    $hist = CaminhoDe $dados 'historico'
    if (Test-Path $hist) { Remove-Item $hist -Recurse -Force }
    New-Item -ItemType Directory -Path $hist -Force | Out-Null

    @{ Cartorio='cartorio-01'; Bucket='backup-aws-ch'; Regiao='us-east-2'; Remoto='cofre'
       PastaDeTrabalho='D:\Cofre'; MbpsMedido=10.6; Pastas=@('E:\DADOS'); Discos=@('E') } |
       ConvertTo-Json | Out-File (CaminhoDe $dados 'cofre.conf') -Encoding UTF8

    $base = 23300000000
    for ($i = 12; $i -ge 1; $i--) {
        $d = (Get-Date).AddDays(-$i)
        $fator = if ($i -eq 5) { 0.35 } elseif ($i -le 2) { 0.55 } else { 1.0 }
        $falhas = if ($i -eq 5) { 1 } else { 0 }
        $b = [long]($base * $fator)
        @{ Rodando=$false; Terminou=$d.ToUniversalTime().ToString('o'); Progresso=100
           Itens=3; Sucessos=(3-$falhas); Falhas=$falhas; EtapaAtual=''; ItemAtual=''
           Detalhes=@(@{Tipo='vm';Nome='SERVIDOR-CARTORIO';Sucesso=$true;Detalhe='ok';Bytes=$b;Quando=$d.ToUniversalTime().ToString('o')}) } |
          ConvertTo-Json -Depth 6 | Out-File (Join-Path $hist ($d.ToString('yyyyMMdd-HHmmss') + '.json')) -Encoding UTF8
    }

    $ontem = (Get-Date).AddHours(-9)
    $qd = $ontem.ToUniversalTime().ToString('o')
    @{ Rodando=$false; Terminou=$qd; Progresso=100; Itens=3; Sucessos=3; Falhas=0
       EtapaAtual=''; ItemAtual=''; Mensagem='tudo certo'
       Detalhes=@(
         @{Tipo='vm';    Nome='SERVIDOR-CARTORIO'; Sucesso=$true; Detalhe='production checkpoint'; Bytes=23300000000; Quando=$qd}
         @{Tipo='pasta'; Nome='DADOS';             Sucesso=$true; Detalhe='copia de sombra';       Bytes=4100000000;  Quando=$qd}
         @{Tipo='imagem';Nome='SISTEMA';           Sucesso=$true; Detalhe='wbadmin -allCritical';  Bytes=68000000000; Quando=$qd}) } |
       ConvertTo-Json -Depth 6 | Out-File (CaminhoDe $dados 'estado.json') -Encoding UTF8
}

function LimparCenario {
    foreach ($a in @('cofre.conf','estado.json','modo.txt')) {
        $p = CaminhoDe $dados $a
        if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
    }
    $h = CaminhoDe $dados 'historico'
    if (Test-Path $h) { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
}

<#
    A FOTO PRECISA DE FUNDO, SENAO ELA MENTE.

    Renderizando um elemento sem Background definido, o WPF nao sabe contra o
    que esta desenhando e o ClearType sai errado: o titulo de secao, que e
    branco de verdade (#EAF1F8, conferido na propriedade), aparecia escuro e
    ilegivel na foto.

    Quase "consertei" a cor de um texto que estava certo. A janela de verdade
    pinta o fundo; a foto precisava fazer o mesmo.
#>
function Fotografar($elemento, [string]$arquivo) {
    $tinhaFundo = $null
    $mexeu = $false
    if ($elemento -is [Windows.Controls.Panel] -and -not $elemento.Background) {
        $elemento.Background = Pincel $Cores.Fundo
        $mexeu = $true
    } elseif ($elemento -is [Windows.Controls.Border] -and -not $elemento.Background) {
        $tinhaFundo = $elemento.Background
        $elemento.Background = Pincel $Cores.Fundo
        $mexeu = $true
    }

    $elemento.Measure([Windows.Size]::new($Largura, $Altura))
    $elemento.Arrange([Windows.Rect]::new(0, 0, $Largura, $Altura))
    $elemento.UpdateLayout()
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap(
        $Largura, $Altura, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($elemento)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $fs = [IO.File]::Create($arquivo)
    try { $enc.Save($fs) } finally { $fs.Close() }

    if ($mexeu) { $elemento.Background = $tinhaFundo }
}

Write-Host ''
Write-Host '  fotografando as telas do CH.Com Cofre'
Write-Host ''

MontarCenario
try {
    . (Join-Path $ui 'cofre-ui.ps1') -NaoAbrir

    $telas = @(
        @{ Menu='mnuPainel';    Arquivo='1-painel.png' }
        @{ Menu='mnuProtegido'; Arquivo='2-protegido.png' }
        @{ Menu='mnuExecutar';  Arquivo='3-executar.png' }
        @{ Menu='mnuRestaurar'; Arquivo='4-restaurar.png' }
        @{ Menu='mnuHistorico'; Arquivo='5-historico.png' }
        @{ Menu='mnuDestino';   Arquivo='6-destino.png' }
        @{ Menu='mnuChave';     Arquivo='7-chave.png' }
        @{ Menu='mnuConfig';    Arquivo='8-configuracao.png' }
    )

    foreach ($t in $telas) {
        $item = $janela.FindName($t.Menu)
        if (-not $item) { continue }
        $item.IsChecked = $true
        $arq = Join-Path $Saida $t.Arquivo
        Fotografar $janela.Content $arq
        Write-Host ("    {0,-14} -> {1}" -f $t.Menu, $t.Arquivo)
    }

    <#
        O assistente tambem, passo a passo. E onde o cartorio comeca, e ate
        hoje ninguem tinha olhado para ele fora do momento de usar.
    #>
    . (Join-Path $ui 'assistente.ps1') -NaoAbrir
    for ($p = 1; $p -le 7; $p++) {
        $W.Passo = $p
        Renderizar
        $arq = Join-Path $Saida ("assistente-$p.png")
        Fotografar $janela.Content $arq
        Write-Host ("    assistente {0}   -> assistente-{0}.png" -f $p)
    }

} finally { LimparCenario }

Write-Host ''
Write-Host ("  {0} foto(s) em {1}" -f @(Get-ChildItem $Saida -Filter *.png).Count, $Saida)
Write-Host ''
