<#
================================================================================
  CH.Com Cofre - montar o instalador .exe

  Transforma a pasta do pacote num UNICO arquivo executavel, com o icone da
  CH.Com, que o cliente recebe e abre com dois cliques.

  POR QUE UM .EXE E NAO UM .ZIP

  O que se entrega hoje e um .zip que a pessoa precisa descompactar, achar o
  INSTALAR.bat la dentro e clicar nele. Cada um desses passos e um lugar para
  dar errado: descompactar "so o .bat", rodar de dentro do zip, esquecer de
  descompactar. Num parque de 38 cartorios, um desses acontece.

  COMO, SEM INSTALAR NADA

  O iexpress.exe ja vem no Windows desde sempre. Ele empacota a pasta inteira
  num executavel auto-extraivel que roda um comando ao terminar - no caso, o
  proprio INSTALAR.bat.

  Nao e MSI e nao pretende ser: nao aparece em "Adicionar ou remover
  programas" pelo instalador em si (quem cuida disso e o instalar-cofre.ps1).
  Em troca, nao exige ferramenta nenhuma para montar.

  USO
      powershell -ExecutionPolicy Bypass -File montar-instalador.ps1
================================================================================
#>

[CmdletBinding()]
param([string]$Saida = '')

$ErrorActionPreference = 'Stop'
$raiz = $PSScriptRoot
if (-not $Saida) { $Saida = Join-Path $raiz 'dist' }
. (Join-Path $raiz 'agente\modulos\comum.ps1')

Marca
Titulo 'Montando os instaladores .exe'

$iexpress = Join-Path $env:SystemRoot 'System32\iexpress.exe'
if (-not (Test-Path $iexpress)) {
    Erro 'o iexpress.exe nao existe nesta maquina - sem ele nao da para montar o .exe'
    exit 1
}

<#
    Monta um .exe a partir de uma pasta.

    O iexpress le um arquivo .SED - um .ini antigo, de 1997, com secoes de
    nome fixo. Cada arquivo precisa aparecer DUAS vezes: uma na lista
    [SourceFiles0] e outra em [Strings] com um apelido FILE0, FILE1... Errar
    essa dupla contagem e o jeito classico de o pacote sair sem arquivo.

    Subpasta o iexpress NAO empacota. Por isso o que entra aqui e o .zip
    inteiro mais um .bat que o descompacta e chama o instalador - duas pecas,
    e a arvore chega inteira do outro lado.
#>
function MontarExe {
    param(
        [Parameter(Mandatory)] [string]$Zip,
        [Parameter(Mandatory)] [string]$ExeFinal,
        [Parameter(Mandatory)] [string]$Titulo,
        [Parameter(Mandatory)] [string]$Instalador
    )

    $trabalho = CaminhoDe $env:TEMP ('cofre-exe-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $trabalho -Force | Out-Null
    try {
        Copy-Item $Zip (CaminhoDe $trabalho 'pacote.zip') -Force

        <#
            O .bat que roda depois da extracao.

            Descompacta num lugar proprio - e nao na pasta temporaria do
            iexpress, que some assim que o .exe termina - e so entao chama o
            instalador. Sem isso, o instalador rodaria em cima de arquivos
            que estao sendo apagados debaixo dele.
        #>
        $abrir = @"
@echo off
title $Titulo
set ALVO=%LOCALAPPDATA%\CH.Com Cofre - instalacao
if exist "%ALVO%" rmdir /s /q "%ALVO%"
mkdir "%ALVO%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%~dp0pacote.zip' -DestinationPath '%ALVO%' -Force"
if not exist "%ALVO%\CH.Com-Cofre\$Instalador" (
    echo.
    echo Nao consegui descompactar o pacote.
    echo.
    pause
    exit /b 1
)
call "%ALVO%\CH.Com-Cofre\$Instalador"
"@
        [System.IO.File]::WriteAllText((CaminhoDe $trabalho 'abrir.bat'), $abrir,
            [System.Text.UTF8Encoding]::new($false))

        $sed = CaminhoDe $trabalho 'receita.sed'
        $conteudo = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$ExeFinal
FriendlyName=$Titulo
AppLaunched=cmd /c abrir.bat
PostInstallCmd=<None>
FILE0="abrir.bat"
FILE1="pacote.zip"
[SourceFiles]
SourceFiles0=$trabalho\
[SourceFiles0]
%FILE0%=
%FILE1%=
"@
        [System.IO.File]::WriteAllText($sed, $conteudo, [System.Text.ASCIIEncoding]::new())

        if (Test-Path $ExeFinal) { Remove-Item $ExeFinal -Force }

        <#
            O iexpress e um programa de JANELA, e volta na hora.

            Chamado direto, ele devolve o controle antes de escrever qualquer
            coisa - e a conferencia logo abaixo dizia "nao gerou o arquivo"
            sobre um trabalho que ainda nem tinha comecado. Com -Wait, o codigo
            de saida passa a valer alguma coisa.
        #>
        $p = Microsoft.PowerShell.Management\Start-Process $iexpress `
            -ArgumentList @('/N', '/Q', $sed) -PassThru -Wait
        if (-not (Test-Path $ExeFinal)) {
            Erro ("o iexpress terminou com codigo $($p.ExitCode) e nao gerou $ExeFinal")
            return $false
        }
        $mb = [math]::Round((Get-Item $ExeFinal).Length / 1MB, 1)
        Ok ("$(Split-Path $ExeFinal -Leaf)  ($mb MB)")
        return $true

    } finally { Remove-Item $trabalho -Recurse -Force -ErrorAction SilentlyContinue }
}

$zipCartorio = CaminhoDe $Saida 'CH.Com-Cofre.zip'
$zipGerente  = CaminhoDe $Saida 'CH.Com-Cofre-GERENTE.zip'
foreach ($z in @($zipCartorio, $zipGerente)) {
    if (-not (Test-Path $z)) {
        Erro "falta $z - rode o montar-pacote.ps1 antes"
        exit 1
    }
}

$okA = MontarExe -Zip $zipCartorio -ExeFinal (CaminhoDe $Saida 'CH.Com-Cofre-Instalador.exe') `
    -Titulo 'CH.Com Cofre - instalacao' -Instalador 'INSTALAR.bat'
$okB = MontarExe -Zip $zipGerente -ExeFinal (CaminhoDe $Saida 'CH.Com-Cofre-Instalador-GERENTE.exe') `
    -Titulo 'CH.Com Cofre - instalacao do gerente' -Instalador 'INSTALAR-GERENTE.bat'

Write-Host ''
if ($okA -and $okB) {
    Caixa @('INSTALADORES PRONTOS',
            '',
            'CH.Com-Cofre-Instalador.exe          -> cartorios',
            'CH.Com-Cofre-Instalador-GERENTE.exe  -> so a CH.Com',
            '',
            'Um arquivo so. Dois cliques e pronto.') 'Green'
} else {
    Erro 'algum instalador nao foi gerado'
    exit 1
}
Write-Host ''
