@echo off
cd /d "%~dp0"
if not exist "%~dp0MyZapret.exe" (
 echo MyZapret.exe is missing. Extract the entire ZIP and check Windows Security protection history.
 pause
 exit /b 1
)
start "" "%~dp0MyZapret.exe"
if errorlevel 1 pause
