@echo off
setlocal
cd /d "%~dp0"
title Backup Log Setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Setup.ps1" %*
echo.
pause
