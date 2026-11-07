@echo off
rem Double-click launcher for garnet-boot.ps1
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0garnet-boot.ps1"
