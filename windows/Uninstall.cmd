@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0BuildSupport\Uninstall.ps1"
set "KARIM_SCRIPT_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %KARIM_SCRIPT_EXIT%
