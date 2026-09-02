<#
================================================================================
  CH.Com Cofre - trocar a marca

  Pega UMA imagem sua e gera o icone do programa em todos os tamanhos que o
  Windows usa.

  POR QUE ISTO EXISTE

  O icone que estava no projeto era um rascunho - um quadrado azul com "CH".
  Trocar a marca a mao exige ferramenta de imagem e conhecimento do formato
  .ico, que guarda VARIAS imagens de tamanhos diferentes num arquivo so.

  O Windows escolhe qual usar conforme o lugar: 16 pixels na barra de tarefas,
  32 no atalho pequeno, 48 no medio, 256 no icone grande. Um .ico com um
  tamanho so fica borrado em todos os outros.

  USO
      powershell -ExecutionPolicy Bypass -File trocar-logo.ps1 -Imagem "C:\...\logo.png"

  A imagem NAO precisa ser quadrada: a margem e aparada e o recorte sai
  centrado no desenho. PNG com fundo transparente fica melhor, mas JPG serve.
================================================================================
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Imagem,
    # Mostra o que seria feito sem gravar nada por cima da marca atual.
    [switch]$Simular
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$aqui = $PSScriptRoot
if (-not (Test-Path $Imagem)) { Write-Host "  nao achei: $Imagem" -f Red; exit 1 }

<#
    APARAR A MARGEM ANTES DE CORTAR.

    Cortar o retangulo no quadrado, direto, funciona - e desperdica o icone.
    Logo costuma vir com margem larga em volta. Cortado assim, o icone de 32
    pixels fica com a marca em 18 e ar em volta.

    Entao primeiro se descobre onde a imagem REALMENTE comeca - varrendo ate
    achar pixel diferente do fundo - e so depois se corta o quadrado, centrado
    no que sobrou.

    O fundo e adivinhado pelo pixel do canto superior esquerdo, que e onde ele
    esta em qualquer logo. Transparente conta como fundo tambem.
#>
function AparaMargem($imagem, [int]$tolerancia = 12) {
    $b = New-Object System.Drawing.Bitmap($imagem)
    try {
        $fundo = $b.GetPixel(0, 0)
        $x1 = $b.Width; $y1 = $b.Height; $x2 = -1; $y2 = -1

        # Amostra de 2 em 2: numa imagem de 1000x1000 sao 250 mil leituras em
        # vez de 1 milhao, e a borda nao se move por causa disso.
        for ($y = 0; $y -lt $b.Height; $y += 2) {
            for ($x = 0; $x -lt $b.Width; $x += 2) {
                $c = $b.GetPixel($x, $y)
                $eFundo = $false
                if ($c.A -lt 16) { $eFundo = $true }
                elseif ($fundo.A -ge 16 -and
                        [math]::Abs($c.R - $fundo.R) -le $tolerancia -and
                        [math]::Abs($c.G - $fundo.G) -le $tolerancia -and
                        [math]::Abs($c.B - $fundo.B) -le $tolerancia) { $eFundo = $true }
                if ($eFundo) { continue }
                if ($x -lt $x1) { $x1 = $x }
                if ($x -gt $x2) { $x2 = $x }
                if ($y -lt $y1) { $y1 = $y }
                if ($y -gt $y2) { $y2 = $y }
            }
        }
        if ($x2 -lt 0) { return @{ X = 0; Y = 0; L = $b.Width; A = $b.Height } }
        return @{ X = $x1; Y = $y1; L = ($x2 - $x1 + 1); A = ($y2 - $y1 + 1) }
    } finally { $b.Dispose() }
}

<#
    Corta o quadrado, centrado no desenho.

    O lado e o MAIOR entre largura e altura do conteudo, para nada da marca
    ficar de fora. Num logo largo sobra ar em cima e embaixo; melhor sobrar ar
    do que perder metade do desenho.

    Os 6% de respiro impedem que o desenho encoste na borda, que fica apertado
    na barra de tarefas.
#>
function CortarQuadrado($imagem, $caixa) {
    $lado = [int]([math]::Max($caixa.L, $caixa.A) * 1.06)
    $cx = $caixa.X + ($caixa.L / 2)
    $cy = $caixa.Y + ($caixa.A / 2)

    $bmp = New-Object System.Drawing.Bitmap($lado, $lado)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.Clear([System.Drawing.Color]::Transparent)
        $destino = New-Object System.Drawing.Rectangle(0, 0, $lado, $lado)
        $origem = New-Object System.Drawing.Rectangle(
            [int]($cx - $lado / 2), [int]($cy - $lado / 2), $lado, $lado)
        $g.DrawImage($imagem, $destino, $origem, [System.Drawing.GraphicsUnit]::Pixel)
    } finally { $g.Dispose() }
    return $bmp
}

<#
    Redimensiona com qualidade.

    O redimensionamento padrao do .NET borra linha fina - e a marca da CH.Com
    tem contorno metalico e texto pequeno, que somem num 16x16 mal feito.
#>
function Redimensionar($imagem, [int]$lado) {
    $bmp = New-Object System.Drawing.Bitmap($lado, $lado)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.DrawImage($imagem, 0, 0, $lado, $lado)
    } finally { $g.Dispose() }
    return $bmp
}

<#
    Escreve o .ico a mao.

    O .NET nao sabe gravar um .ico com varios tamanhos - Icon.Save() guarda um
    so. O formato e simples e antigo: cabecalho de 6 bytes, uma entrada de 16
    bytes por imagem, e os PNGs em seguida.

    O campo de largura tem UM byte: 256 nao cabe, e o formato manda escrever
    ZERO para dizer 256. Errar isso faz o Windows usar o de 128 no lugar e
    mostrar o icone grande borrado.
#>
function GravarIco([string]$arquivo, $imagens) {
    $fs = [IO.File]::Create($arquivo)
    $bw = New-Object IO.BinaryWriter($fs)
    try {
        $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$imagens.Count)

        $dados = @()
        foreach ($img in $imagens) {
            $ms = New-Object IO.MemoryStream
            $img.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $dados += ,$ms.ToArray()
            $ms.Dispose()
        }

        $inicio = 6 + (16 * $imagens.Count)
        for ($i = 0; $i -lt $imagens.Count; $i++) {
            $lado = $imagens[$i].Width
            $b = [byte]$(if ($lado -ge 256) { 0 } else { $lado })
            $bw.Write($b); $bw.Write($b)
            $bw.Write([byte]0); $bw.Write([byte]0)
            $bw.Write([UInt16]1); $bw.Write([UInt16]32)
            $bw.Write([UInt32]$dados[$i].Length)
            $bw.Write([UInt32]$inicio)
            $inicio += $dados[$i].Length
        }
        foreach ($d in $dados) { $bw.Write($d) }
    } finally { $bw.Dispose(); $fs.Dispose() }
}

# ==============================================================================

Write-Host ''
Write-Host '  CH.Com Cofre - trocando a marca' -ForegroundColor Cyan
Write-Host ''

$carregada = [System.Drawing.Image]::FromFile((Resolve-Path $Imagem).Path)
Write-Host ("  origem            : {0}x{1} pixels" -f $carregada.Width, $carregada.Height)

$caixa = AparaMargem $carregada
$aprov = [math]::Round((($caixa.L * $caixa.A) / ($carregada.Width * $carregada.Height)) * 100)
Write-Host ("  marca dentro dela : {0}x{1}  ({2}% do arquivo)" -f $caixa.L, $caixa.A, $aprov)
if ($aprov -lt 90) {
    Write-Host ("  aparando          : {0}% de margem em volta" -f (100 - $aprov)) -ForegroundColor Cyan
}

$orig = CortarQuadrado $carregada $caixa
$carregada.Dispose()
Write-Host ("  recorte quadrado  : {0}x{1}, centrado no desenho" -f $orig.Width, $orig.Height)
if ($orig.Width -lt 200) {
    Write-Host '  AVISO: a marca e pequena no arquivo - o icone grande pode sair borrado.' -ForegroundColor Yellow
}
Write-Host ''

# Do MAIOR para o menor. O Windows escolhe sozinho; programas que leem so o
# primeiro quadro pegam o bom.
$lados = @(256, 128, 64, 48, 32, 24, 16)
$imagens = @()
foreach ($l in $lados) { $imagens += (Redimensionar $orig $l) }

if ($Simular) {
    $amostra = Join-Path $env:TEMP 'chcom-previa.png'
    (Redimensionar $orig 256).Save($amostra, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "  SIMULACAO - nada foi gravado na marca do projeto." -ForegroundColor Yellow
    Write-Host "  Previa de como ficaria: $amostra"
} else {
    GravarIco (Join-Path $aqui 'chcom.ico') $imagens
    Write-Host ("  [OK] chcom.ico     ({0} tamanhos: {1})" -f $lados.Count, ($lados -join ', ')) -ForegroundColor Green

    $g256 = Redimensionar $orig 256
    $g256.Save((Join-Path $aqui 'logo-256.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    $g256.Dispose()
    Write-Host '  [OK] logo-256.png' -ForegroundColor Green

    Write-Host ''
    Write-Host '  Marca trocada. Remonte o pacote para levar ao cartorio:' -ForegroundColor Cyan
    Write-Host '     powershell -ExecutionPolicy Bypass -File montar-pacote.ps1'
}

foreach ($i in $imagens) { $i.Dispose() }
$orig.Dispose()
Write-Host ''
