# Faz o Painel Backup CH.Com rodar sozinho, sempre.
#
#   npm run instalar-servico
#
# ---------------------------------------------------------------------------
# O PROBLEMA QUE ISTO RESOLVE
#
# Até agora o painel rodava com "npm run dev", preso a uma janela de terminal:
# fechou a janela, encerrou a sessão ou reiniciou a máquina, o painel morre.
# E um painel de monitoramento que cai em silêncio é pior que não ter painel,
# porque a tela vazia parece "nenhum problema" em vez de "não estou olhando".
#
# Aqui ele vira uma Tarefa Agendada do Windows que:
#   - sobe sozinha quando a máquina liga (antes mesmo de alguém fazer logon)
#   - reinicia sozinha se o processo cair
#   - roda o código COMPILADO (dist/), não o modo de desenvolvimento
#
# Tarefa Agendada em vez de Serviço do Windows de propósito: serviço exige
# um invólucro para processos Node (nssm, node-windows) — mais uma peça para
# manter. A tarefa faz o mesmo com o que já vem no Windows.
# ---------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string]$Nome = 'PainelBackupCHCom',
    [switch]$Remover
)

$ErrorActionPreference = 'Stop'
$projeto = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Ok($t)    { Write-Host "  $t" -ForegroundColor Green }
function Aviso($t) { Write-Host "  $t" -ForegroundColor Yellow }
function Erro($t)  { Write-Host "  $t" -ForegroundColor Red }

Write-Host ""

# --- remover ----------------------------------------------------------------

if ($Remover) {
    $t = Get-ScheduledTask -TaskName $Nome -ErrorAction SilentlyContinue
    if ($t) {
        Stop-ScheduledTask -TaskName $Nome -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $Nome -Confirm:$false
        Ok "Tarefa '$Nome' removida. O painel nao sobe mais sozinho."
    } else {
        Aviso "Tarefa '$Nome' nao existe."
    }
    Write-Host ""
    exit 0
}

# --- localizar o node -------------------------------------------------------

$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) {
    foreach ($c in @("$env:ProgramFiles\nodejs\node.exe", "${env:ProgramFiles(x86)}\nodejs\node.exe")) {
        if (Test-Path $c) { $node = $c; break }
    }
}
if (-not $node) { Erro "Nao encontrei o node.exe. Instale o Node.js."; exit 1 }
Ok "node: $node"

# --- compilar ---------------------------------------------------------------
#
# A tarefa roda dist/, nao src/. Rodar TypeScript direto em producao
# significaria carregar o compilador a cada inicio e engolir erros de tipo
# que o build pegaria.

Write-Host ""
Write-Host "  Compilando..." -ForegroundColor Cyan
Push-Location $projeto
try {
    & npm run build 2>&1 | Select-Object -Last 3
    if ($LASTEXITCODE -ne 0) { Erro "A compilacao falhou. Corrija os erros e rode de novo."; exit 1 }
} finally { Pop-Location }

$entrada = Join-Path $projeto 'dist\index.js'
if (-not (Test-Path $entrada)) { Erro "Nao encontrei $entrada apos compilar."; exit 1 }
Ok "compilado: $entrada"

# --- registrar a tarefa -----------------------------------------------------

$acao = New-ScheduledTaskAction -Execute $node -Argument "`"$entrada`"" -WorkingDirectory $projeto

# Dois gatilhos: ao ligar a maquina e ao fazer logon. O de boot cobre o
# servidor que reinicia de madrugada sem ninguem por perto; o de logon cobre
# maquina de mesa, onde tarefas de boot as vezes sao bloqueadas por politica.
$gatilhos = @(
    New-ScheduledTaskTrigger -AtStartup
    New-ScheduledTaskTrigger -AtLogOn
)

$config = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)   # sem limite: e um servidor, roda sempre

$existente = Get-ScheduledTask -TaskName $Nome -ErrorAction SilentlyContinue
if ($existente) {
    Stop-ScheduledTask -TaskName $Nome -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $Nome -Confirm:$false
    Aviso "tarefa anterior substituida"
}

# Duas tentativas, nesta ordem:
#
#   1. Tarefa de MAQUINA (-RunLevel Highest + gatilho de boot). Sobe antes de
#      qualquer logon — é o que se quer num servidor que reinicia de
#      madrugada. Exige Administrador.
#
#   2. Tarefa de USUARIO, só com gatilho de logon. Não exige Administrador,
#      mas o painel só sobe depois que alguém entra na máquina.
#
# O plano B existe porque exigir elevação transformaria "arruma o painel" em
# "abra outro terminal como administrador e tente de novo" — e um painel que
# sobe no logon já é muito melhor que um que morre ao fechar a janela.
$registrada = $false
$comBoot = $false

try {
    Register-ScheduledTask -TaskName $Nome -Action $acao -Trigger $gatilhos `
        -Settings $config -Description 'Painel Backup CH.Com - monitoramento dos backups dos cartorios' `
        -RunLevel Highest -Force -ErrorAction Stop | Out-Null
    $registrada = $true
    $comBoot = $true
    Ok "tarefa '$Nome' registrada (sobe junto com a maquina)"
} catch {
    try {
        Register-ScheduledTask -TaskName $Nome -Action $acao `
            -Trigger (New-ScheduledTaskTrigger -AtLogOn) `
            -Settings $config -Description 'Painel Backup CH.Com - monitoramento dos backups dos cartorios' `
            -Force -ErrorAction Stop | Out-Null
        $registrada = $true
        Ok "tarefa '$Nome' registrada (sobe quando voce faz logon)"
        Aviso "sem Administrador, so consegui o gatilho de logon."
        Aviso "para subir junto com a maquina, rode este comando como Administrador."
    } catch {
        Aviso "o registro de Tarefas Agendadas esta bloqueado nesta maquina."
        Aviso "usando a pasta de Inicializacao do Windows."

        # Plano C: um atalho na pasta Inicializar. Não precisa de permissão
        # nenhuma — é uma pasta do próprio usuário.
        #
        # Vai por .vbs e não por .bat porque um .bat deixaria uma janela preta
        # de console aberta o tempo todo na área de trabalho. O WScript.Shell
        # com o modo de janela 0 inicia o Node sem janela alguma.
        $inicializar = [Environment]::GetFolderPath('Startup')
        $vbs = Join-Path $inicializar 'PainelBackupCHCom.vbs'

        $conteudo = @"
' Inicia o Painel Backup CH.Com sem abrir janela.
' Gerado por: npm run instalar-servico
' Para desativar: npm run remover-servico (ou apague este arquivo)
Set sh = CreateObject("WScript.Shell")
sh.CurrentDirectory = "$projeto"
sh.Run """$node"" ""$entrada""", 0, False
"@
        [System.IO.File]::WriteAllText($vbs, $conteudo, [System.Text.Encoding]::Default)

        if (Test-Path $vbs) {
            $registrada = $true
            Ok "atalho de inicializacao criado (sobe quando voce faz logon)"
            Write-Host "     $vbs"
        } else {
            Erro "nao consegui criar o atalho de inicializacao."
            exit 1
        }
    }
}

# --- iniciar e conferir -----------------------------------------------------

# Se o painel ja estiver rodando em modo dev, a porta esta ocupada e a tarefa
# subiria e morreria. Melhor avisar do que deixar o operador achando que
# funcionou.
$emUso = $false
$c = New-Object System.Net.Sockets.TcpClient
try { $c.Connect('127.0.0.1', 3000); $emUso = $c.Connected } catch { } finally { $c.Close() }

if ($emUso) {
    Write-Host ""
    Aviso "A porta 3000 ja esta em uso (provavelmente o 'npm run dev')."
    Aviso "Feche aquela janela; no proximo logon o painel sobe sozinho."
    Write-Host ""
    exit 0
}

# Sobe agora, sem esperar o proximo logon.
try {
    if (Get-ScheduledTask -TaskName $Nome -ErrorAction SilentlyContinue) {
        Start-ScheduledTask -TaskName $Nome
    } else {
        Start-Process $node -ArgumentList "`"$entrada`"" -WorkingDirectory $projeto -WindowStyle Hidden
    }
} catch {
    Start-Process $node -ArgumentList "`"$entrada`"" -WorkingDirectory $projeto -WindowStyle Hidden
}

$noAr = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 1
    $c = New-Object System.Net.Sockets.TcpClient
    try { $c.Connect('127.0.0.1', 3000); $noAr = $c.Connected } catch { } finally { $c.Close() }
    if ($noAr) { break }
}

Write-Host ""
if ($noAr) {
    Write-Host "  ===============================================================" -ForegroundColor Green
    Write-Host "     PAINEL NO AR - http://localhost:3000" -ForegroundColor Green
    Write-Host "     $(if ($comBoot) { 'Sobe sozinho quando a maquina ligar.' } else { 'Sobe sozinho quando voce fizer logon.' })" -ForegroundColor Green
    Write-Host "  ===============================================================" -ForegroundColor Green
} else {
    Erro "A tarefa foi criada mas o painel nao respondeu."
    Write-Host "  Veja o estado com:  Get-ScheduledTask -TaskName $Nome | Get-ScheduledTaskInfo"
}
Write-Host ""
