[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$WorkspaceDir = "."
)

$ErrorActionPreference = "Stop"

if (-not [System.IO.Path]::IsPathRooted($WorkspaceDir)) {
    $WorkspaceDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $WorkspaceDir))
}

if (-not (Test-Path -LiteralPath $WorkspaceDir)) {
    throw "Workspace klasoru bulunamadi: $WorkspaceDir"
}

Write-Host "Temizlik baslatiliyor..."
Write-Host "Calisma klasoru: $WorkspaceDir"

$pathsToRemove = @(
    "input",
    "output",
    "download-report.csv",
    "process-report.csv",
    "run-summary.json",
    "pipeline-master-log.jsonl"
)

foreach ($item in $pathsToRemove) {
    $target = Join-Path $WorkspaceDir $item
    if (Test-Path -LiteralPath $target) {
        if ($PSCmdlet.ShouldProcess($target, "Sil")) {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
            Write-Host "Silindi: $item"
        }
    } else {
        Write-Host "Bulunamadi (atlanan): $item"
    }
}

# Her sifirlama sonrasi pipeline klasorleri tekrar hazir olur.
New-Item -ItemType Directory -Force -Path (Join-Path $WorkspaceDir "input") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $WorkspaceDir "output") | Out-Null

Write-Host ""
Write-Host "Temizlik tamamlandi."
Write-Host "input/output klasorleri yeniden olusturuldu."
