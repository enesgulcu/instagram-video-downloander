[CmdletBinding()]
param(
    [string]$WorkspaceDir = ".",
    [string]$LinksFile = "instagram-links.txt",
    [string]$InputDir = "input",
    [string]$OutputDir = "output",
    [string]$BgmFile = "",
    [double]$CutSeconds = 5.0,
    [double]$Contrast = 1.28,
    [double]$Saturation = 1.35,
    [double]$Brightness = 0.04,
    [double]$AudioGainDb = 3.5,
    [string]$Watermark = "evitemiz.com",
    [ValidateSet("fast","balanced","quality")]
    [string]$Profile = "balanced",
    [string]$RunReportFile = "run-summary.json",
    [string]$MasterLogFile = "pipeline-master-log.jsonl",
    [int]$ParallelWorkers = 1,
    [ValidateSet("auto","cpu","gpu")]
    [string]$EncoderMode = "auto"
)

$ErrorActionPreference = "Stop"

function Ensure-ToolOnPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$ExecutableName
    )
    if (Get-Command $Name -ErrorAction SilentlyContinue) { return }
    $pkgRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $pkgRoot) {
        $foundExe = Get-ChildItem -Path $pkgRoot -Recurse -Filter $ExecutableName -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if ($foundExe) {
            $toolDir = Split-Path -Path $foundExe -Parent
            $env:Path = "$toolDir;$env:Path"
        }
    }
}

if (-not [System.IO.Path]::IsPathRooted($WorkspaceDir)) {
    $WorkspaceDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $WorkspaceDir))
}

$linksPath = Join-Path $WorkspaceDir $LinksFile
$inputPath = Join-Path $WorkspaceDir $InputDir
$outputPath = Join-Path $WorkspaceDir $OutputDir
$downloadScript = Join-Path $WorkspaceDir "download-instagram.ps1"
$processScript = Join-Path $WorkspaceDir "process-videos.ps1"
$downloadReportFile = Join-Path $WorkspaceDir "download-report.csv"
$processReportFile = Join-Path $WorkspaceDir "process-report.csv"
$runReportPath = Join-Path $WorkspaceDir $RunReportFile
$masterLogPath = Join-Path $WorkspaceDir $MasterLogFile

if (-not (Test-Path -LiteralPath $downloadScript)) {
    throw "download-instagram.ps1 bulunamadi: $downloadScript"
}
if (-not (Test-Path -LiteralPath $processScript)) {
    throw "process-videos.ps1 bulunamadi: $processScript"
}
if (-not (Test-Path -LiteralPath $linksPath)) {
    throw "Link dosyasi bulunamadi: $linksPath"
}

New-Item -ItemType Directory -Force -Path $inputPath | Out-Null
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null

$start = Get-Date
Ensure-ToolOnPath -Name "ffmpeg" -ExecutableName "ffmpeg.exe"

function Test-NvencAvailable {
    try {
        $encoders = & ffmpeg -hide_banner -encoders 2>$null
        return ($LASTEXITCODE -eq 0 -and (($encoders -join "`n") -match "h264_nvenc"))
    } catch {
        return $false
    }
}

$gpuAvailable = Test-NvencAvailable
$useGpu = $false
if ($EncoderMode -eq "gpu") {
    if (-not $gpuAvailable) { throw "GPU encoder (h264_nvenc) bulunamadi." }
    $useGpu = $true
} elseif ($EncoderMode -eq "auto") {
    $useGpu = $gpuAvailable
}

switch ($Profile) {
    "fast" {
        $CutSeconds = 5.0
        $Contrast = 1.15
        $Saturation = 1.20
        $Brightness = 0.03
        $AudioGainDb = 2.5
        $encodePreset = if ($useGpu) { "p5" } else { "veryfast" }
        $crf = 24
    }
    "quality" {
        $CutSeconds = 5.0
        $Contrast = 1.28
        $Saturation = 1.35
        $Brightness = 0.04
        $AudioGainDb = 3.5
        $encodePreset = if ($useGpu) { "p7" } else { "slow" }
        $crf = if ($useGpu) { 20 } else { 18 }
    }
    default {
        $encodePreset = if ($useGpu) { "p6" } else { "medium" }
        $crf = if ($useGpu) { 21 } else { 20 }
    }
}
$videoEncoder = if ($useGpu) { "h264_nvenc" } else { "libx264" }

Write-Host "1/2 Linklerden videolar indiriliyor..."
& powershell -ExecutionPolicy Bypass -File $downloadScript `
    -UrlListFile $linksPath `
    -OutputDir $inputPath `
    -SkipIfExists `
    -MaxRetry 3 `
    -DownloadReportFile $downloadReportFile
if ($LASTEXITCODE -ne 0) {
    throw "Indirme adimi basarisiz oldu."
}

$videoExts = @("*.mp4","*.mov","*.mkv","*.avi","*.m4v")
$downloadedVideos = foreach ($ext in $videoExts) { Get-ChildItem -Path $inputPath -File -Filter $ext -ErrorAction SilentlyContinue }
$downloadedVideos = $downloadedVideos | Sort-Object FullName -Unique
if (-not $downloadedVideos -or $downloadedVideos.Count -eq 0) {
    throw "Indirme sonrasi input klasorunde video bulunamadi. Daha fazla reel linki toplayin veya minimum izlenmeyi dusurun."
}

Write-Host "2/2 Videolar isleniyor..."
$processArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $processScript,
    "-InputDir", $inputPath,
    "-OutputDir", $outputPath,
    "-CutSeconds", "$CutSeconds",
    "-Contrast", "$Contrast",
    "-Saturation", "$Saturation",
    "-Brightness", "$Brightness",
    "-AudioGainDb", "$AudioGainDb",
    "-Watermark", "$Watermark",
    "-VideoEncoder", "$videoEncoder",
    "-EncodePreset", "$encodePreset",
    "-Crf", "$crf",
    "-MaxRetry", "2",
    "-ProcessReportFile", "$processReportFile",
    "-ParallelWorkers", "$ParallelWorkers"
)

if (-not [string]::IsNullOrWhiteSpace($BgmFile)) {
    $processArgs += @("-BgmFile", (Join-Path $WorkspaceDir $BgmFile))
}

& powershell @processArgs
if ($LASTEXITCODE -ne 0) {
    throw "Video isleme adimi basarisiz oldu."
}

Write-Host ""
Write-Host "Tum adimlar tamamlandi."
Write-Host "Cikti klasoru: $outputPath"

$end = Get-Date
$downloadRows = @()
if (Test-Path -LiteralPath $downloadReportFile) {
    $downloadRows = Import-Csv -LiteralPath $downloadReportFile |
        Where-Object { $_.date -and ([datetime]$_.date) -ge $start }
}
$processRows = @()
if (Test-Path -LiteralPath $processReportFile) {
    $processRows = Import-Csv -LiteralPath $processReportFile |
        Where-Object { $_.date -and ([datetime]$_.date) -ge $start }
}

$summary = [pscustomobject]@{
    started_at = $start.ToString("s")
    finished_at = $end.ToString("s")
    duration_seconds = [Math]::Round(($end - $start).TotalSeconds, 2)
    profile = $Profile
    encoder_mode = $EncoderMode
    video_encoder = $videoEncoder
    parallel_workers = $ParallelWorkers
    links_file = $linksPath
    download_total = $downloadRows.Count
    download_errors = ($downloadRows | Where-Object { $_.status -eq "error" }).Count
    process_total = $processRows.Count
    process_errors = ($processRows | Where-Object { $_.status -eq "error" }).Count
    output_count = (Get-ChildItem -Path $outputPath -File -Filter "*.mp4" -ErrorAction SilentlyContinue).Count
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $runReportPath -Encoding UTF8
Write-Host "Run raporu: $runReportPath"

$downloadErrors = $downloadRows | Where-Object { $_.status -eq "error" } | Select-Object -First 5
$processErrors = $processRows | Where-Object { $_.status -eq "error" } | Select-Object -First 5
$masterEntry = [pscustomobject]@{
    started_at = $summary.started_at
    finished_at = $summary.finished_at
    duration_seconds = $summary.duration_seconds
    profile = $summary.profile
    encoder_mode = $summary.encoder_mode
    video_encoder = $summary.video_encoder
    parallel_workers = $summary.parallel_workers
    download_total = $summary.download_total
    download_errors = $summary.download_errors
    process_total = $summary.process_total
    process_errors = $summary.process_errors
    output_count = $summary.output_count
    top_download_errors = @($downloadErrors)
    top_process_errors = @($processErrors)
}
Add-Content -LiteralPath $masterLogPath -Value ($masterEntry | ConvertTo-Json -Depth 6 -Compress)
Write-Host "Master log: $masterLogPath"
