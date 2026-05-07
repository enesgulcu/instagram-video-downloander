[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Test-Tool {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget bulunamadi. Microsoft App Installer gerekli."
}

$needFfmpeg = -not (Test-Tool -Name "ffmpeg")
$needYtdlp = -not (Test-Tool -Name "yt-dlp")

if (-not $needFfmpeg -and -not $needYtdlp) {
    Write-Host "Tum temel araclar zaten kurulu."
    exit 0
}

if ($needFfmpeg) {
    Write-Host "FFmpeg kuruluyor..."
    winget install -e --id Gyan.FFmpeg --accept-package-agreements --accept-source-agreements
}

if ($needYtdlp) {
    Write-Host "yt-dlp kuruluyor..."
    winget install -e --id yt-dlp.yt-dlp --accept-package-agreements --accept-source-agreements
}

Write-Host "Kurulum tamamlandi. Yeni terminal acarsan PATH guncel hali kullanilir."
