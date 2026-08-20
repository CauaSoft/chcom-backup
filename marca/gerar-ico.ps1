# Gera branding\logo\chcom.ico com varias resolucoes dentro.
#
#   powershell -ExecutionPolicy Bypass -File branding\gerar-ico.ps1
#
# ---------------------------------------------------------------------------
# POR QUE NAO USAR O favicon.ico QUE JA EXISTE
#
# Aquele tem uma unica imagem de 32x32, feita para a aba do navegador. O
# Windows usa tamanhos diferentes conforme o lugar: 16 na barra de tarefas,
# 32 na area de trabalho, 48 no modo "icones grandes" e 256 no painel de
# visualizacao. Com um unico 32x32, o Windows estica e o logo fica borrado
# justamente na area de trabalho, que e onde o cliente olha.
#
# Este script monta o .ico na mao porque o .NET nao tem API para escrever
# ICO com varias imagens - o Icon.Save() grava so uma. O formato e simples:
# um cabecalho de 6 bytes, uma entrada de 16 bytes por imagem, e os dados.
# Desde o Windows Vista os dados podem ser PNG direto, que e o que fazemos.
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$dir = Join-Path $PSScriptRoot 'logo'
$origem = Join-Path $dir 'logo-512.png'

if (-not (Test-Path $origem)) {
    Write-Error "Nao encontrei $origem. Rode gerar-logos.ps1 antes."
    exit 1
}

$tamanhos = @(16, 24, 32, 48, 64, 128, 256)
$src = [System.Drawing.Bitmap]::FromFile($origem)

# Gera cada tamanho como PNG em memoria
$imagens = @()
foreach ($t in $tamanhos) {
    $bmp = New-Object System.Drawing.Bitmap($t, $t)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($src, 0, 0, $t, $t)
    $g.Dispose()

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    $imagens += [pscustomobject]@{ Tamanho = $t; Dados = $ms.ToArray() }
    $ms.Dispose()
}
$src.Dispose()

# --- monta o arquivo .ico ---------------------------------------------------

$saida = Join-Path $dir 'chcom.ico'
$fs = [System.IO.File]::Create($saida)
$bw = New-Object System.IO.BinaryWriter($fs)

# ICONDIR
$bw.Write([uint16]0)                  # reservado, sempre 0
$bw.Write([uint16]1)                  # tipo 1 = icone
$bw.Write([uint16]$imagens.Count)

# O primeiro byte de dados vem depois do cabecalho e de todas as entradas
$offset = 6 + (16 * $imagens.Count)

foreach ($img in $imagens) {
    # 256 e gravado como 0: o campo tem um byte so, e 256 nao cabe
    $dim = if ($img.Tamanho -ge 256) { 0 } else { $img.Tamanho }

    $bw.Write([byte]$dim)             # largura
    $bw.Write([byte]$dim)             # altura
    $bw.Write([byte]0)                # cores da paleta (0 = sem paleta)
    $bw.Write([byte]0)                # reservado
    $bw.Write([uint16]1)              # planos
    $bw.Write([uint16]32)             # bits por pixel
    $bw.Write([uint32]$img.Dados.Length)
    $bw.Write([uint32]$offset)

    $offset += $img.Dados.Length
}

foreach ($img in $imagens) { $bw.Write($img.Dados) }

$bw.Close(); $fs.Close()

$kb = [math]::Round((Get-Item $saida).Length / 1KB, 1)
Write-Host "gerado: $saida ($kb KB, $($imagens.Count) resolucoes: $($tamanhos -join ', '))"
