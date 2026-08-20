@echo off
chcp 65001 >nul 2>&1
title Remover a marca CH.Com Backup

rem =============================================================================
rem  Remove a marca CH.Com e devolve o Duplicati ao visual original.
rem
rem  NAO desconfigura o envio de relatorios para o painel, e nao mexe em
rem  nenhum backup. So o visual volta ao padrao.
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
echo      Remover a marca CH.Com (o Duplicati volta ao visual padrao)
echo   ===============================================================
echo.
echo   Isto NAO desliga o backup e NAO apaga configuracao nenhuma.
echo.
set /p RESPOSTA="   Continuar? (S/N): "
if /i not "%RESPOSTA%"=="S" (
    echo.
    echo   Cancelado. Nada foi alterado.
    echo.
    pause
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0aplicar-no-cartorio.ps1" -Desfazer

echo.
echo   Pressione qualquer tecla para fechar...
pause >nul
