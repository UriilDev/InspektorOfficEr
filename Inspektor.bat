@echo off
setlocal
title InspektorOfficEr

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Inspektor.ps1"
set RC=%errorlevel%

if %RC% equ 0 (
    echo.
    echo Done.
    timeout /t 3 >nul
) else (
    echo.
    echo FINISHED WITH CODE %RC% - see messages above
    pause
)
endlocal & exit /b %RC%
