@echo off
setlocal
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "copy_sfc.ps1" "%~1"
set "exitCode=%ERRORLEVEL%"
if %exitCode% NEQ 0 (
	pause
)
endlocal
exit /b %exitCode%
