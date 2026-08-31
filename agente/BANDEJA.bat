@echo off
title CH.Com Cofre
cd /d "%~dp0"
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0bandeja.ps1"
