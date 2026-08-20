# Gera todos os tamanhos de logo a partir do logo OFICIAL da CH.Com.
#
# Use este script quando o LOGO_PRETA_PNG.png real estiver disponivel.
#
# COMO USAR
#   1. Salve o logo oficial como  branding\logo\logo-512.png
#      (512 x 512 pixels, PNG, FUNDO TRANSPARENTE)
#   2. Rode:
#        powershell -ExecutionPolicy Bypass -File branding\redimensionar-logo.ps1
#   3. Rode  branding\instalar.ps1  como Administrador para aplicar.
#
# O script sobrescreve logo-256.png, logo-32.png e favicon.ico, mas nunca
# toca no logo-512.png de origem.

Add-Type -AssemblyName System.Drawing

$dir = Join-Path $PSScriptRoot 'logo'
$origem = Join-Path $dir 'logo-512.png'

if (-not (Test-Path $origem)) {
    Write-Error "Nao encontrei $origem. Salve o logo oficial nesse caminho, em 512x512 com fundo transparente."
    exit 1
}

$src = [System.Drawing.Bitmap]::FromFile($origem)
if ($src.Width -ne $src.Height) {
    Write-Warning "O logo nao e quadrado ($($src.Width)x$($src.Height)). Ele vai ser esticado. O ideal e 512x512."
}

function Resize-Logo {
    param([int]$Size, [string]$Arquivo)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($src, 0, 0, $Size, $Size)
    $bmp.Save($Arquivo, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Host "gerado: $Arquivo ($Size x $Size)"
}

Resize-Logo -Size 256 -Arquivo (Join-Path $dir 'logo-256.png')   # ngax: img/logo.png
Resize-Logo -Size 64  -Arquivo (Join-Path $dir 'logo-64.png')    # ngclient: window.BRANDING_LOGO
Resize-Logo -Size 32  -Arquivo (Join-Path $dir 'logo-32.png')    # favicon do ngclient

$png32 = [System.Drawing.Bitmap]::FromFile((Join-Path $dir 'logo-32.png'))
$hicon = $png32.GetHicon()
$icone = [System.Drawing.Icon]::FromHandle($hicon)
$fs = [System.IO.File]::Create((Join-Path $dir 'favicon.ico'))
$icone.Save($fs)
$fs.Close(); $icone.Dispose(); $png32.Dispose()
Write-Host "gerado: favicon.ico"

$src.Dispose()

# O oem-custom.js embute o logo, então precisa ser refeito junto.
& (Join-Path $PSScriptRoot 'gerar-oem-js.ps1')

Write-Host ""
Write-Host "Pronto. Agora rode branding\instalar.ps1 como Administrador."
