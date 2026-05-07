@echo off
setlocal
cd /d "%~dp0"

echo FFmpeg otomasyon baslatiliyor...
powershell -NoProfile -ExecutionPolicy Bypass -File ".\start-run.ps1"

echo.
echo Islem tamamlandi. Cikmak icin bir tusa basin.
pause >nul
