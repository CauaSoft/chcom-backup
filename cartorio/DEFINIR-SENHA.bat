@echo off
chcp 65001 > nul
title CH.Com Backup - Definir a senha de acesso

rem Pede administrador sozinho: reiniciar o programa e gravar a configuracao
rem precisa disso, e sem elevacao falha com uma mensagem que nao ajuda.
net session > nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo.
echo   Abrindo a janela para voce digitar a senha...
echo   (ela aparece em alguns segundos)
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0definir-senha.ps1"

echo.
pause
