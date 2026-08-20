@echo off
chcp 65001 >nul 2>&1
title Corrigir destino s3-aws dos backups

rem =============================================================================
rem  Corrige o erro "The backend protocol s3-aws is not supported".
rem
rem  Mostra o que vai mudar, pede confirmacao, e so entao altera.
rem  Nao mexe nos arquivos que ja estao na nuvem.
rem =============================================================================

net session >nul 2>&1
if %errorlevel% equ 0 goto :executar
echo.
echo   Pedindo permissao de administrador...
echo   Clique em SIM na janela do Windows.
echo.
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
exit /b

:executar
cd /d "%~dp0"

cls
echo.
echo   ===============================================================
echo      Corrigir destino dos backups: s3-aws://  para  s3://
echo   ===============================================================
echo.
echo   Primeiro vou MOSTRAR o que seria alterado, sem mexer em nada.
echo.
pause

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0corrigir-s3.ps1"

echo.
echo   ===============================================================
echo.
set /p RESPOSTA="   Aplicar essas alteracoes de verdade? (S/N): "
if /i not "%RESPOSTA%"=="S" (
    echo.
    echo   Cancelado. Nada foi alterado.
    echo.
    pause
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0corrigir-s3.ps1" -Aplicar

echo.
echo   Pressione qualquer tecla para fechar...
pause >nul
