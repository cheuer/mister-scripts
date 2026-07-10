@echo off
setlocal
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "copy_sfc.ps1" "%~1"
endlocal
