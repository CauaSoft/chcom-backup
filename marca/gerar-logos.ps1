# Gera os logos PLACEHOLDER da CH.Com.
#
# Isto NAO e o logo definitivo. Serve so para provar que a troca de logo
# funciona, enquanto o LOGO_PRETA_PNG.png real nao chega.
#
# Para usar o logo real: apague este script, coloque o PNG oficial em
# 512x512 com fundo transparente como branding/logo-512.png e rode
# branding/redimensionar-logo.ps1 (gera os tamanhos derivados).
#
# Uso:  powershell -ExecutionPolicy Bypass -File branding\gerar-logos.ps1

Add-Type -AssemblyName System.Drawing

$dir = Join-Path $PSScriptRoot 'logo'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

$azul = [System.Drawing.Color]::FromArgb(255, 0, 168, 255)   # #00A8FF
$fundo = [System.Drawing.Color]::FromArgb(255, 20, 22, 28)   # #14161C

function New-Logo {
    param([int]$Size, [string]$Arquivo)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::Transparent)

    # Quadrado arredondado azul neon, com uma margem de 6% de cada lado
    $m = [int]($Size * 0.06)
    $lado = $Size - (2 * $m)
    $raio = [int]($Size * 0.22)

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($m, $m, $raio, $raio, 180, 90)
    $path.AddArc($m + $lado - $raio, $m, $raio, $raio, 270, 90)
    $path.AddArc($m + $lado - $raio, $m + $lado - $raio, $raio, $raio, 0, 90)
    $path.AddArc($m, $m + $lado - $raio, $raio, $raio, 90, 90)
    $path.CloseFigure()

    $brushAzul = New-Object System.Drawing.SolidBrush($azul)
    $g.FillPath($brushAzul, $path)

    # As letras "CH" em cima, na cor do fundo escuro
    $fonte = New-Object System.Drawing.Font('Segoe UI', ($Size * 0.36), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $brushTexto = New-Object System.Drawing.SolidBrush($fundo)
    $rect = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
    $g.DrawString('CH', $fonte, $brushTexto, $rect, $fmt)

    $bmp.Save($Arquivo, [System.Drawing.Imaging.ImageFormat]::Png)

    $g.Dispose(); $bmp.Dispose(); $path.Dispose()
    $brushAzul.Dispose(); $brushTexto.Dispose(); $fonte.Dispose(); $fmt.Dispose()

    Write-Host "gerado: $Arquivo ($Size x $Size)"
}

New-Logo -Size 512 -Arquivo (Join-Path $dir 'logo-512.png')
New-Logo -Size 256 -Arquivo (Join-Path $dir 'logo-256.png')   # ngax: img/logo.png
New-Logo -Size 64  -Arquivo (Join-Path $dir 'logo-64.png')    # ngclient: window.BRANDING_LOGO
New-Logo -Size 32  -Arquivo (Join-Path $dir 'logo-32.png')    # favicon do ngclient

# favicon.ico a partir do PNG de 32px
$src = [System.Drawing.Bitmap]::FromFile((Join-Path $dir 'logo-32.png'))
$hicon = $src.GetHicon()
$icone = [System.Drawing.Icon]::FromHandle($hicon)
$fs = [System.IO.File]::Create((Join-Path $dir 'favicon.ico'))
$icone.Save($fs)
$fs.Close(); $icone.Dispose(); $src.Dispose()
Write-Host "gerado: favicon.ico"

# O oem-custom.js embute o logo, então precisa ser refeito sempre que o logo
# muda. Chamar daqui evita o erro de trocar o PNG e esquecer o JS — que daria
# um logo novo na interface clássica e o velho na nova.
& (Join-Path $PSScriptRoot 'gerar-oem-js.ps1')
