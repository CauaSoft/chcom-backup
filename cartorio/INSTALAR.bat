@echo off
chcp 65001 >nul 2>&1
title Instalar CH.Com Backup

rem =============================================================================
rem  CH.Com Backup - instalador de um clique
rem
rem  O tecnico da um duplo clique neste arquivo e acabou. Nada de abrir
rem  PowerShell, nada de digitar comando, nada de lembrar parametro.
rem
rem  Ele se eleva sozinho (o Windows pede a confirmacao do UAC), chama o
rem  script de verdade e para no final para o resultado poder ser lido.
rem =============================================================================

rem --- ja estamos como administrador? ------------------------------------------
net session >nul 2>&1
if %errorlevel% equ 0 goto :executar

rem --- nao estamos: reabre este mesmo .bat elevado ------------------------------
rem
rem O "cd /d" la embaixo e essencial: ao elevar, o Windows joga o diretorio
rem atual para C:\Windows\System32, e sem voltar para a pasta do pacote o
rem script nao acharia a pasta marca\ ao lado dele.
echo.
echo   Pedindo permissao de administrador...
echo   Clique em SIM na janela do Windows.
echo.
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   Nao foi possivel pedir a elevacao automaticamente.
    echo   Clique com o botao direito neste arquivo e escolha
    echo   "Executar como administrador".
    echo.
    pause
)
exit /b

:executar
cd /d "%~dp0"

cls
echo.
echo   ===============================================================
echo      CH.Com Backup - aplicando a identidade da CH.Com
echo   ===============================================================
echo.

if not exist "%~dp0aplicar-no-cartorio.ps1" (
    echo   ERRO: nao encontrei aplicar-no-cartorio.ps1 nesta pasta.
    echo.
    echo   Copie a PASTA INTEIRA para o servidor, nao so este arquivo.
    echo.
    pause
    exit /b 1
)

if not exist "%~dp0marca" (
    echo   ERRO: nao encontrei a pasta "marca" aqui do lado.
    echo.
    echo   Copie a PASTA INTEIRA para o servidor, nao so este arquivo.
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0aplicar-no-cartorio.ps1"
set CODIGO=%errorlevel%

echo.
echo   ===============================================================
if %CODIGO% equ 0 (
    echo      PRONTO. Abra o Duplicati e pressione Ctrl+F5 no navegador.
) else (
    echo      TERMINOU COM AVISO - leia as mensagens acima.
)
echo   ===============================================================
echo.
echo   Pressione qualquer tecla para fechar...
pause >nul
