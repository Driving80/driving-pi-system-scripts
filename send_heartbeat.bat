@echo off
REM Wrapper for heartbeat sender — runs PowerShell script from Task Scheduler
REM Log file: C:\Users\%username%\AppData\Local\Temp\heartbeat_sender.log

setlocal enabledelayedexpansion
set "SCRIPT_PATH=%~dp0send_heartbeat.ps1"
set "LOG_FILE=%TEMP%\heartbeat_sender.log"

REM Append to log
echo [%date% %time%] Starting heartbeat sender >> "%LOG_FILE%"

REM Run PowerShell with script bypass
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" >> "%LOG_FILE%" 2>&1

echo [%date% %time%] Heartbeat sender exited >> "%LOG_FILE%"