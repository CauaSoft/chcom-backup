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
  32 no atalho pequeno, 48 no medio, 256 no icone grande da area de trabalho.
  Um .ico com um tamanho so fica borrado em todos os outros.

  USO
      powershell -ExecutionPolicy Bypass -File trocar-logo.ps1 -Imagem "C:\...\logo.png"

  A imagem deve ser QUADRADA e ter pelo menos 256x256. PNG com fundo
  transparente fica melhor, mas JPG tambem serve.
================================================================================
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Imagem
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$aqui = $PSScriptRoot
if (-not (Test-Path $Imagem)) { Write-Host "  nao achei: $Imagem" -f Red; exit 1 }

Write-Host ''
Write-Host '  CH.Com Cofre - trocando a marca' -ForegroundColor Cyan
Write-Host ''

$orig = [System.Drawing.Image]::FromFile((Resolve-Path $Imagem).Path)
Write-Host ("  origem: {0}x{1} pixels" -f $orig.Width, $orig.Height)
if ($orig.Width -lt 256 -or $orig.Height -lt 256) {
    Write-Host '  AVISO: menor que 256x256 - o icone grande vai sair borrado.' -ForegroundColor Yellow
}
if ([math]::Abs($orig.Width - $orig.Height) -gt 2) {
    Write-Host '  AVISO: a imagem nao e quadrada - ela sera esticada.' -ForegroundColor Yellow
}

<#
    Redimensiona com qualidade.

    O redimensionamento padrao do .NET borra linha fina - e a marca da CH.Com
    tem contorno metalico e texto pequeno, que somem num 16x16 mal feito.
    HighQualityBicubic custa alguns milissegundos e salva o icone pequeno.
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

    O .NET nao sabe gravar um .ico com varios tamanhos - o Icon.Save() so
    guarda um. O formato e simples e antigo: um cabecalho de 6 bytes, uma
    entrada de 16 bytes por imagem, e os PNGs em seguida.

    O campo de largura tem UM byte: 256 nao cabe, e o formato manda escrever
    ZERO para dizer 256. Errar isso faz o Windows mostrar o icone grande
    borrado, usando o de 128 no lugar.
#>
function GravarIco([string]$arquivo, $imagens) {
    $fs = [IO.File]::Create($arquivo)
    $bw = New-Object IO.BinaryWriter($fs)
    try {
        $bw.Write([UInt16]0)                  # reservado
        $bw.Write([UInt16]1)                  # 1 = icone
        $bw.Write([UInt16]$imagens.Count)

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
            $bw.Write([byte]$(if ($lado -ge 256) { 0 } else { $lado }))   # largura
            $bw.Write([byte]$(if ($lado -ge 256) { 0 } else { $lado }))   # altura
            $bw.Write([byte]0)                # cores na paleta
            $bw.Write([byte]0)                # reservado
            $bw.Write([UInt16]1)              # planos
            $bw.Write([UInt16]32)             # bits por pixel
            $bw.Write([UInt32]$dados[$i].Length)
            $bw.Write([UInt32]$inicio)
            $inicio += $dados[$i].Length
        }
        foreach ($d in $dados) { $bw.Write($d) }
    } finally { $bw.Dispose(); $fs.Dispose() }
}

<#
    DO MAIOR PARA O MENOR, e isso importa.

    O Windows escolhe o tamanho certo dentro do .ico sozinho. O WPF nao: ele
    pega o PRIMEIRO quadro do arquivo e usa aquele. Com a lista comecando em
    16, a janela do programa abria com um icone de 16 pixels esticado - visto
    e medido: "a janela carrega: 16x16".

    Comecando pelo 256, a janela pega o grande e o Windows continua escolhendo
    o dele. Os dois ficam certos sem precisar mexer no codigo da interface.
#>
$lados = @(256, 128, 64, 48, 32, 24, 16)
$imagens = @()
foreach ($l in $lados) { $imagens += (Redimensionar $orig $l) }

$ico = Join-Path $aqui 'chcom.ico'
GravarIco $ico $imagens
Write-Host ("  [OK] chcom.ico  ({0} tamanhos: {1})" -f $lados.Count, ($lados -join ', ')) -ForegroundColor Green

# O logo de 256 e usado pela bandeja e pelas telas.
$png = Join-Path $aqui 'logo-256.png'
$g256 = Redimensionar $orig 256
$g256.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host '  [OK] logo-256.png' -ForegroundColor Green

foreach ($i in $imagens) { $i.Dispose() }
$g256.Dispose()
$orig.Dispose()

Write-Host ''
Write-Host '  Marca trocada. Remonte o pacote para levar ao cartorio:' -ForegroundColor Cyan
Write-Host '     powershell -ExecutionPolicy Bypass -File montar-pacote.ps1'
Write-Host ''
