@echo off
title CH.Com Cofre
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0interface\cofre-ui.ps1"
