@echo off
chcp 65001 >nul 2>&1
title CH.Com Cofre - Instalacao

rem Marcador contra fila infinita de UAC: "net session" tambem falha quando o
rem servico Servidor esta parado, e sem o marcador a maquina pediria elevacao
rem para sempre.
if "%~1"=="elevado" goto executar
net session >nul 2>&1
if not errorlevel 1 goto executar

rem As ASPAS em '%~f0' nao sao enfeite. Este pacote e entregue numa pasta
rem chamada "CH.Com Cofre - INSTALAR NO SERVIDOR" - com espacos. Sem aspas, o
rem PowerShell le so o primeiro pedaco do caminho, nao acha o arquivo, e o
rem instalador simplesmente NAO RODA, sem dizer nada.
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList 'elevado' -Verb RunAs" >nul 2>&1
exit /b

:executar
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar-cofre.ps1"
