@echo off
chcp 65001 >nul 2>&1
title CH.Com Cofre - Diagnostico

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnostico-cofre.ps1"
echo.
echo   Pressione qualquer tecla para fechar...
pause >nul
