# Gera os icones da bandeja (ao lado do relogio) com a marca CH.Com.
#
#   powershell -ExecutionPolicy Bypass -File branding\gerar-icones-bandeja.ps1
#
# Estes sao os UNICOS elementos da marca que exigem recompilar o programa: o
# Duplicati carrega estes PNGs de dentro do proprio executavel, em tempo de
# execucao. Nenhum truque de CSS ou de atalho alcanca eles.
#
# ---------------------------------------------------------------------------
# POR QUE SAO SEIS, E NAO UM SO
#
# O icone da bandeja nao e enfeite: e o unico aviso que o operador do cartorio
# tem sem abrir nada. Ele precisa distinguir, de relance e num icone de 16
# pixels, se o backup esta rodando, parado, com aviso ou com erro.
#
# Por isso cada estado tem COR e FORMA proprias. Depender so da cor excluiria
# quem tem daltonismo -- e vermelho contra verde e justamente o par que a
# forma mais comum de daltonismo nao distingue.
#
#   normal        logo limpo
#   running       seta (esta trabalhando)
#   pause         duas barras
#   warning       triangulo amarelo
#   error         circulo vermelho com X
#   disconnected  cinza, sem cor (sem contato com o servidor)
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$dir = Join-Path $PSScriptRoot 'logo'
$origem = Join-Path $dir 'logo-512.png'
$saidaDir = Join-Path $dir 'bandeja'

if (-not (Test-Path $origem)) { Write-Error "Falta $origem. Rode gerar-logos.ps1 antes."; exit 1 }
if (-not (Test-Path $saidaDir)) { New-Item -ItemType Directory -Path $saidaDir -Force | Out-Null }

$TAM = 256
$src = [System.Drawing.Bitmap]::FromFile($origem)

function Nova-Base([bool]$cinza) {
    $bmp = New-Object System.Drawing.Bitmap($TAM, $TAM)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.Clear([System.Drawing.Color]::Transparent)

    if ($cinza) {
        # Matriz que converte para tons de cinza pelos pesos de luminancia
        # (0.299 / 0.587 / 0.114). Um cinza "na media" escureceria o azul
        # demais e o icone sumiria na barra escura do Windows.
        $m = New-Object System.Drawing.Imaging.ColorMatrix
        $m.Matrix00 = 0.299; $m.Matrix01 = 0.299; $m.Matrix02 = 0.299
        $m.Matrix10 = 0.587; $m.Matrix11 = 0.587; $m.Matrix12 = 0.587
        $m.Matrix20 = 0.114; $m.Matrix21 = 0.114; $m.Matrix22 = 0.114
        $m.Matrix33 = 0.55   # mais transparente: "sem contato"
        $m.Matrix44 = 1

        $attr = New-Object System.Drawing.Imaging.ImageAttributes
        $attr.SetColorMatrix($m)
        $rect = New-Object System.Drawing.Rectangle(0, 0, $TAM, $TAM)
        $g.DrawImage($src, $rect, 0, 0, $src.Width, $src.Height,
                     [System.Drawing.GraphicsUnit]::Pixel, $attr)
        $attr.Dispose()
    } else {
        $g.DrawImage($src, 0, 0, $TAM, $TAM)
    }

    return @{ Bitmap = $bmp; Graphics = $g }
}

# O emblema ocupa 44% do icone e fica no canto inferior direito: e o que ainda
# da para distinguir quando o Windows encolhe tudo para 16 pixels.
function Emblema($g, [System.Drawing.Color]$cor) {
    $d = [int]($TAM * 0.44)
    $x = $TAM - $d - 6
    $y = $TAM - $d - 6

    # Contorno na cor do fundo escuro, para o emblema nao se fundir com o logo
    $fundo = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 20, 22, 28))
    $g.FillEllipse($fundo, $x - 5, $y - 5, $d + 10, $d + 10)
    $fundo.Dispose()

    $b = New-Object System.Drawing.SolidBrush($cor)
    $g.FillEllipse($b, $x, $y, $d, $d)
    $b.Dispose()

    return @{ X = $x; Y = $y; D = $d }
}

$branco = [System.Drawing.Color]::White
$escuro = [System.Drawing.Color]::FromArgb(255, 20, 22, 28)

function Salvar($item, [string]$nome) {
    $arq = Join-Path $saidaDir $nome
    $item.Graphics.Dispose()
    $item.Bitmap.Save($arq, [System.Drawing.Imaging.ImageFormat]::Png)
    $item.Bitmap.Dispose()
    Write-Host "  gerado: $nome"
}

# --- normal -----------------------------------------------------------------
Salvar (Nova-Base $false) 'normal.png'

# --- running: seta ----------------------------------------------------------
$i = Nova-Base $false
$e = Emblema $i.Graphics ([System.Drawing.Color]::FromArgb(255, 34, 197, 94))
$cx = $e.X + $e.D / 2; $cy = $e.Y + $e.D / 2; $r = $e.D * 0.24
$seta = @(
    (New-Object System.Drawing.PointF(($cx - $r * 0.7), ($cy - $r))),
    (New-Object System.Drawing.PointF(($cx - $r * 0.7), ($cy + $r))),
    (New-Object System.Drawing.PointF(($cx + $r), $cy))
)
$b = New-Object System.Drawing.SolidBrush($branco)
$i.Graphics.FillPolygon($b, $seta)
$b.Dispose()
Salvar $i 'normal-running.png'

# --- pause: duas barras -----------------------------------------------------
$i = Nova-Base $false
$e = Emblema $i.Graphics ([System.Drawing.Color]::FromArgb(255, 245, 165, 36))
$cx = $e.X + $e.D / 2; $cy = $e.Y + $e.D / 2; $bw = $e.D * 0.13; $bh = $e.D * 0.42
$b = New-Object System.Drawing.SolidBrush($escuro)
$i.Graphics.FillRectangle($b, ($cx - $bw * 1.8), ($cy - $bh / 2), $bw, $bh)
$i.Graphics.FillRectangle($b, ($cx + $bw * 0.8), ($cy - $bh / 2), $bw, $bh)
$b.Dispose()
Salvar $i 'normal-pause.png'

# --- warning: triangulo -----------------------------------------------------
$i = Nova-Base $false
$e = Emblema $i.Graphics ([System.Drawing.Color]::FromArgb(255, 245, 165, 36))
$cx = $e.X + $e.D / 2; $cy = $e.Y + $e.D / 2; $r = $e.D * 0.30
$tri = @(
    (New-Object System.Drawing.PointF($cx, ($cy - $r))),
    (New-Object System.Drawing.PointF(($cx - $r * 0.92), ($cy + $r * 0.62))),
    (New-Object System.Drawing.PointF(($cx + $r * 0.92), ($cy + $r * 0.62)))
)
$b = New-Object System.Drawing.SolidBrush($escuro)
$i.Graphics.FillPolygon($b, $tri)
$b.Dispose()
Salvar $i 'normal-warning.png'

# --- error: X ---------------------------------------------------------------
$i = Nova-Base $false
$e = Emblema $i.Graphics ([System.Drawing.Color]::FromArgb(255, 243, 67, 107))
$cx = $e.X + $e.D / 2; $cy = $e.Y + $e.D / 2; $r = $e.D * 0.22
$caneta = New-Object System.Drawing.Pen($branco, [float]($e.D * 0.14))
$caneta.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$caneta.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$i.Graphics.DrawLine($caneta, ($cx - $r), ($cy - $r), ($cx + $r), ($cy + $r))
$i.Graphics.DrawLine($caneta, ($cx + $r), ($cy - $r), ($cx - $r), ($cy + $r))
$caneta.Dispose()
Salvar $i 'normal-error.png'

# --- disconnected: cinza ----------------------------------------------------
Salvar (Nova-Base $true) 'normal-disconnected.png'

$src.Dispose()
Write-Host ""
Write-Host "6 icones de bandeja gerados em: $saidaDir"
