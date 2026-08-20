@echo off
chcp 65001 >nul 2>&1
title Resumo dos avisos - CH.Com Backup

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0resumir-avisos.ps1"
echo.
echo   Pressione qualquer tecla para fechar...
pause >nul
