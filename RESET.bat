@echo off
setlocal
cd /d "%~dp0"

echo FFmpeg verileri sifirlaniyor...
powershell -NoProfile -ExecutionPolicy Bypass -File ".\reset-workspace.ps1" -WorkspaceDir "."
if errorlevel 1 (
    echo.
    echo Sifirlama sirasinda hata olustu.
    echo Cikmak icin bir tusa basin.
    pause >nul
    exit /b 1
)

echo.
echo Tum calisma verileri sifirlandi.
echo Cikmak icin bir tusa basin.
pause >nul
