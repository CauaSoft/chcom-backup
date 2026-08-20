@echo off
chcp 65001 > nul
title CH.Com Backup - Aplicar as regras padrao

net session > nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo.
echo   Aplicando as regras padrao do CH.Com neste servidor:
echo     - copia de arquivos abertos (VSS)
echo     - filtros que tiram lixeira, temporarios e cache
echo     - mais tentativas quando o link oscila
echo     - dados guardados em Glacier Deep Archive (mais barato)
echo.
echo   IMPORTANTE: em Deep Archive, restaurar exige descongelar
echo   antes, o que leva 12 horas. Leia o arquivo
echo   RESTAURAR-DO-ARQUIVO-MORTO.txt desta pasta ANTES de precisar.
echo.
echo   Uma janela vai pedir a senha do CH.Com Backup.
echo.

rem -ArquivoMorto: manda os dados para o Glacier Deep Archive.
rem Combinado com o cliente: janela de recuperacao de 48 horas, e o custo
rem manda. Liga junto --no-auto-compact e --backup-test-samples=0, que sao
rem obrigatorios quando os arquivos ficam congelados - ver o cabecalho do
rem .ps1 e o RESTAURAR-DO-ARQUIVO-MORTO.txt.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0aplicar-regras.ps1" -ArquivoMorto

echo.
pause
