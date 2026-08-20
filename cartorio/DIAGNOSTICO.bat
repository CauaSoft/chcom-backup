@echo off
chcp 65001 >nul 2>&1
title Diagnostico CH.Com Backup

net session >nul 2>&1
if %errorlevel% equ 0 goto :executar
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
exit /b

:executar
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnostico.ps1"
echo.
echo   Pressione qualquer tecla para fechar...
pause >nul
