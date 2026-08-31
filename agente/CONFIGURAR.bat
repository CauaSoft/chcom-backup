@echo off
title CH.Com Cofre - configuracao
cd /d "%~dp0"

rem O assistente grava em ProgramData e registra tarefas no Agendador, entao
rem precisa de administrador.
rem
rem O marcador "elevado" existe para nao girar em circulo: o teste de
rem elevacao usa "net session", que tambem falha quando o servico Servidor
rem esta parado. Sem o marcador, uma maquina nessa situacao pediria elevacao,
rem falharia no mesmo teste, pediria de novo - uma fila infinita de avisos do
rem Windows. Com ele, a tentativa acontece no maximo uma vez.
if "%~1"=="elevado" goto rodar

net session >nul 2>&1
if not errorlevel 1 goto rodar

powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList 'elevado' -Verb RunAs" >nul 2>&1
exit /b

:rodar
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0interface\assistente.ps1"
if errorlevel 1 (
    echo.
    echo O assistente parou antes de terminar. Os detalhes estao em:
    echo   %ProgramData%\CH.Com Cofre\erro-assistente.txt
    echo.
    pause
    exit /b
)

rem O assistente fecha ao terminar. Sem esta linha a tela simplesmente SOME -
rem quem acabou de configurar fica olhando para a area de trabalho, sem saber
rem se deu certo. Visto em teste.
rem
rem Vai pelo explorer de proposito: assim o programa abre como o usuario
rem normal, e nao herdando o administrador deste .bat.
start "" explorer.exe "%~dp0CH.Com Cofre.bat"
