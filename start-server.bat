@echo off
title Azure SQL Metro Bridge Server
echo ==========================================================
echo Starting Azure SQL Metro Bridge Server on http://localhost:8080/
echo Zero dependencies - Native PowerShell & .NET SqlClient
echo ==========================================================
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
pause
