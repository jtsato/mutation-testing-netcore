@echo off
setlocal
 
:: Captura o diretório atual onde o usuário invocou o comando
set "TARGET_DIR=%CD%"
 
:: Invoca o script PowerShell ignorando políticas de execução restritivas
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Bin\update_dotnet_10.ps1" -WorkingDir "%TARGET_DIR%"
 
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERRO] A migracao falhou ou foi interrompida (Codigo de saida: %ERRORLEVEL%).
)