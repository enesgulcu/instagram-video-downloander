[CmdletBinding()]
param(
    [string]$WorkspaceDir = ".",
    [string]$LinksFile = "instagram-links.txt",
    [string]$Profile = "fast"
)

$ErrorActionPreference = "Stop"

if (-not [System.IO.Path]::IsPathRooted($WorkspaceDir)) {
    $WorkspaceDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $WorkspaceDir))
}

if ($Profile -notin @("fast","balanced","quality")) {
    $Profile = "fast"
}

$linksPath = Join-Path $WorkspaceDir $LinksFile
$pipelineScript = Join-Path $WorkspaceDir "run-pipeline.ps1"
$setupScript = Join-Path $WorkspaceDir "setup.ps1"

if (-not (Test-Path -LiteralPath $pipelineScript)) {
    throw "run-pipeline.ps1 bulunamadi: $pipelineScript"
}

if (Test-Path -LiteralPath $setupScript) {
    $runSetup = Read-Host "Eksik araclari kontrol/kurulum yapmak icin E (atlamak icin Enter)"
    if ($null -ne $runSetup) { $runSetup = $runSetup.Trim().ToUpperInvariant() }
    if ($runSetup -eq "E") {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $setupScript
    }
}

Write-Host ""
Write-Host "Otomatik link bulma devre disi."
Write-Host "Lutfen instagram-links.txt dosyasini manuel doldurun."

$parallelWorkers = 1
$encoderMode = "auto"

if (-not (Test-Path -LiteralPath $linksPath)) {
    throw "Link dosyasi bulunamadi: $linksPath"
}

Write-Host ""
Write-Host "Pipeline baslatiliyor..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $pipelineScript -WorkspaceDir $WorkspaceDir -LinksFile $LinksFile -Profile $Profile -ParallelWorkers $parallelWorkers -EncoderMode $encoderMode
if ($LASTEXITCODE -ne 0) {
    throw "Pipeline calismasi basarisiz oldu."
}
