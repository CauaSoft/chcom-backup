# Monta o pacote de instalação que vai para o servidor do cartório.
#
#   powershell -ExecutionPolicy Bypass -File branding\criar-pacote.ps1
#
# Sai um .zip autocontido em branding\dist\. Ele não depende deste
# repositório, nem de Node, nem de nada instalado no servidor do cartório
# além do próprio Duplicati e do PowerShell que já vem no Windows.

$ErrorActionPreference = 'Stop'

$repo = Split-Path $PSScriptRoot -Parent
$webroot = Join-Path $repo 'Duplicati\Server\webroot'
$dist = Join-Path $PSScriptRoot 'dist'
$nome = 'CH.Com-Backup-Instalacao'
$saida = Join-Path $dist $nome

if (-not (Test-Path (Join-Path $PSScriptRoot 'oem-custom.js'))) {
    Write-Error "Falta branding\oem-custom.js. Rode branding\gerar-logos.ps1 antes."
    exit 1
}

if (Test-Path $saida) { Remove-Item $saida -Recurse -Force }
New-Item -ItemType Directory -Path $saida -Force | Out-Null

# Cada item: o que copiar, e para onde dentro de marca\.
# O caminho de destino espelha a estrutura da pasta do Duplicati instalado,
# para o script de aplicação ser uma cópia direta, sem mapeamento na cabeça.
$itens = @(
    @{ de = Join-Path $PSScriptRoot 'oem-custom.css';  para = 'oem-custom.css' }
    @{ de = Join-Path $PSScriptRoot 'oem-custom.js';   para = 'oem-custom.js' }
    @{ de = Join-Path $webroot 'index.html';           para = 'webroot\index.html' }
    @{ de = Join-Path $webroot 'login.html';           para = 'webroot\login.html' }
    @{ de = Join-Path $webroot 'signin.html';          para = 'webroot\signin.html' }
    @{ de = Join-Path $webroot 'theme.html';           para = 'webroot\theme.html' }
    @{ de = Join-Path $webroot 'favicon.ico';          para = 'webroot\favicon.ico' }
    @{ de = Join-Path $webroot 'img\logo.png';         para = 'webroot\img\logo.png' }
    @{ de = Join-Path $webroot 'ngax\index.html';      para = 'webroot\ngax\index.html' }
    @{ de = Join-Path $webroot 'ngax\styles\chcom.css'; para = 'webroot\ngax\styles\chcom.css' }
    @{ de = Join-Path $webroot 'ngax\scripts\services\BrandingService.js'; para = 'webroot\ngax\scripts\services\BrandingService.js' }
    @{ de = Join-Path $webroot 'oem\root\login\oem.css'; para = 'webroot\oem\root\login\oem.css' }
    @{ de = Join-Path $webroot 'oem\root\theme\oem.css'; para = 'webroot\oem\root\theme\oem.css' }
    @{ de = Join-Path $PSScriptRoot 'logo\logo-32.png';  para = 'webroot\ngclient\assets\duplicati-logo.png' }
    # Icone dos atalhos: e o que o cliente ve na area de trabalho
    @{ de = Join-Path $PSScriptRoot 'logo\chcom.ico';    para = 'chcom.ico' }
)

Write-Host ""
Write-Host "  Montando o pacote..."
Write-Host ""

$faltando = @()
foreach ($i in $itens) {
    if (-not (Test-Path $i.de)) { $faltando += $i.de; continue }

    $destino = Join-Path $saida "marca\$($i.para)"
    $pastaDestino = Split-Path $destino -Parent
    if (-not (Test-Path $pastaDestino)) { New-Item -ItemType Directory -Path $pastaDestino -Force | Out-Null }
    Copy-Item $i.de $destino -Force
    Write-Host "    $($i.para)"
}

if ($faltando.Count -gt 0) {
    Write-Host ""
    Write-Error "Arquivos faltando no repositorio:`n  $($faltando -join "`n  ")"
    exit 1
}

Copy-Item (Join-Path $PSScriptRoot 'pacote\aplicar-no-cartorio.ps1') $saida -Force
Copy-Item (Join-Path $PSScriptRoot 'pacote\LEIA-ME.md') $saida -Force

# Os .bat sao a porta de entrada: duplo clique e acabou. O .ps1 continua ali
# para quem precisar dos parametros (token, porta, destino diferente).
Copy-Item (Join-Path $PSScriptRoot 'pacote\INSTALAR.bat') $saida -Force
Copy-Item (Join-Path $PSScriptRoot 'pacote\DESINSTALAR.bat') $saida -Force
Copy-Item (Join-Path $PSScriptRoot 'pacote\DIAGNOSTICO.bat') $saida -Force
Copy-Item (Join-Path $PSScriptRoot 'pacote\diagnostico.ps1') $saida -Force
Copy-Item (Join-Path $PSScriptRoot 'pacote\CORRIGIR-S3.bat') $saida -Force
Copy-Item (Join-Path $PSScriptRoot 'pacote\corrigir-s3.ps1') $saida -Force

# O aviso de licença vai junto: a MIT exige que o texto acompanhe o software
# distribuído, e este pacote é distribuição.
Copy-Item (Join-Path $repo 'LICENSE') (Join-Path $saida 'LICENSE-Duplicati.txt') -Force
Copy-Item (Join-Path $repo 'NOTICE-CHCOM.md') $saida -Force

$zip = Join-Path $dist "$nome.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $saida -DestinationPath $zip -CompressionLevel Optimal

$kb = [math]::Round((Get-Item $zip).Length / 1KB, 1)

Write-Host ""
Write-Host "  Pacote pronto: $zip  ($kb KB)" -ForegroundColor Green
Write-Host ""
Write-Host "  Copie o .zip para o servidor do cartorio, descompacte e rode como"
Write-Host "  Administrador:"
Write-Host ""
Write-Host "    .\aplicar-no-cartorio.ps1 -Token <token> -UrlPainel <endereco>"
Write-Host ""
