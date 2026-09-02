<#
================================================================================
  CH.Com Cofre - instalar no servidor

  Um comando so, que ACHA o pacote sozinho.

  POR QUE ISTO EXISTE

  A instrucao anterior era "copie o zip para uma pasta, abra o PowerShell
  NAQUELA pasta, e rode Expand-Archive .\CH.Com-Cofre*.zip".

  Num servidor, aberto como Administrador, o PowerShell comeca em
  C:\Users\Administrador - e o zip nao esta la. O comando falhou com "O
  caminho '' nao existe", que nao diz nada sobre o que fazer.

  Um instalador que depende de o operador estar na pasta certa nao e um
  instalador. Este procura o pacote nos lugares onde ele realmente estaria, e
  quando nao acha, DIZ ONDE PROCUROU.

  USO
      Cole no PowerShell como Administrador:

      iwr -useb <endereco>/INSTALAR-NO-SERVIDOR.ps1 | iex

      ou, com o arquivo em maos:

      powershell -ExecutionPolicy Bypass -File INSTALAR-NO-SERVIDOR.ps1
================================================================================
#>

[CmdletBinding()]
param(
    # Caminho do .zip ou do .exe, quando voce sabe onde esta.
    [string]$Pacote = ''
)

$ErrorActionPreference = 'Stop'

function Diga([string]$t, [string]$cor = 'Gray') { Write-Host "  $t" -ForegroundColor $cor }

Write-Host ''
Write-Host '  CH.Com Cofre - instalacao' -ForegroundColor Cyan
Write-Host ''

# --- administrador ------------------------------------------------------------
$eu = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $eu.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Diga 'Este comando precisa do PowerShell aberto como Administrador.' 'Red'
    Diga 'Feche, clique com o botao direito no PowerShell e escolha' 'Gray'
    Diga '"Executar como administrador".' 'Gray'
    Write-Host ''
    exit 1
}

# --- achar o pacote -----------------------------------------------------------
<#
    Os lugares onde o pacote REALMENTE estaria.

    Nao adianta procurar so na pasta atual: o PowerShell de Administrador abre
    em C:\Users\Administrador, e ninguem copia o zip para la. Quem copia um
    arquivo para um servidor larga na Area de Trabalho, em Downloads, na raiz
    do C: ou num pendrive.
#>
$ondeProcurar = @(
    (Get-Location).Path
    [Environment]::GetFolderPath('Desktop')
    (Join-Path $env:USERPROFILE 'Downloads')
    (Join-Path $env:PUBLIC 'Desktop')
    'C:\'
    'C:\temp'
    $env:TEMP
)
# Pendrives e discos externos, que e como o pacote costuma chegar num cartorio.
foreach ($u in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' -ErrorAction SilentlyContinue)) {
    $ondeProcurar += ($u.DeviceID + '\')
}

if ($Pacote) {
    if (-not (Test-Path $Pacote)) { Diga "nao achei: $Pacote" 'Red'; exit 1 }
    $achado = Get-Item $Pacote
} else {
    $achado = $null
    foreach ($p in $ondeProcurar) {
        if (-not $p -or -not (Test-Path $p)) { continue }
        $c = @(Get-ChildItem $p -Filter 'CH.Com-Cofre*.zip' -File -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending)
        if ($c.Count -gt 0) { $achado = $c[0]; break }
    }
}

if (-not $achado) {
    Diga 'Nao achei o pacote CH.Com-Cofre.zip. Procurei em:' 'Red'
    foreach ($p in $ondeProcurar) { if ($p) { Diga "   $p" 'DarkGray' } }
    Write-Host ''
    Diga 'Copie o zip para a Area de Trabalho e rode de novo, ou passe o caminho:' 'Yellow'
    Diga '   .\INSTALAR-NO-SERVIDOR.ps1 -Pacote "D:\CH.Com-Cofre.zip"' 'Gray'
    Write-Host ''
    exit 1
}

Diga "pacote: $($achado.FullName)" 'Green'

# --- descompactar e instalar --------------------------------------------------
<#
    Unblock-File antes de tudo.

    Zip copiado de pasta de rede vem com marca de origem, e o Windows recusa
    executar o que sai de dentro dele - inclusive o .ps1 do instalador. Isso
    aparece como "nao e reconhecido como nome de cmdlet", que manda o tecnico
    procurar erro de digitacao num comando certo.
#>
Unblock-File $achado.FullName -ErrorAction SilentlyContinue

$destino = Join-Path $env:TEMP 'cofre-instalacao'
if (Test-Path $destino) { Remove-Item $destino -Recurse -Force -ErrorAction SilentlyContinue }
Expand-Archive -LiteralPath $achado.FullName -DestinationPath $destino -Force
Get-ChildItem $destino -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

$script = Get-ChildItem $destino -Recurse -Filter 'instalar-cofre.ps1' -File | Select-Object -First 1
if (-not $script) {
    Diga 'o zip nao tem o instalador dentro - pacote incompleto ou corrompido.' 'Red'
    exit 1
}

Diga 'instalando...' 'Gray'
Write-Host ''
& $script.FullName
