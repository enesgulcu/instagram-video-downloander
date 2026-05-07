[CmdletBinding()]
param(
    [string]$InputDir = ".\input",
    [string]$OutputDir = ".\output",
    [string]$NotesFileName = "merge-notes.md"
)

$ErrorActionPreference = "Stop"

function Get-InstagramIdFromFileName {
    param([Parameter(Mandatory = $true)][string]$FileName)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $lastUnderscore = $name.LastIndexOf("_")
    if ($lastUnderscore -lt 0 -or $lastUnderscore -ge ($name.Length - 1)) { return "" }
    return $name.Substring($lastUnderscore + 1)
}

function ConvertTo-SingleLineText {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return (($Value -replace "`r", " " -replace "`n", " ") -replace "\s+", " ").Trim()
}

function Escape-MarkdownText {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $escaped = $Value -replace '\\', '\\'
    $escaped = $escaped -replace '\|', '\|'
    return $escaped
}

function Get-SourceVideoMetadata {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$VideoFile)
    $id = Get-InstagramIdFromFileName -FileName $VideoFile.Name
    $metaPath = Join-Path $VideoFile.DirectoryName "$($VideoFile.BaseName).info.json"
    $url = ""
    $description = ""
    if (Test-Path -LiteralPath $metaPath) {
        try {
            $metaRaw = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
            $meta = $metaRaw | ConvertFrom-Json -ErrorAction Stop
            $url = ConvertTo-SingleLineText (($meta.webpage_url, $meta.original_url, $meta.url) | Where-Object { $_ } | Select-Object -First 1)
            $description = ConvertTo-SingleLineText ($meta.description)
        } catch {
        }
    }

    return [pscustomobject]@{
        Name = $VideoFile.Name
        Id = $id
        Url = $url
        Description = $description
    }
}

if (-not (Test-Path -LiteralPath $InputDir)) { throw "Input klasoru bulunamadi: $InputDir" }
if (-not (Test-Path -LiteralPath $OutputDir)) { throw "Output klasoru bulunamadi: $OutputDir" }

$videoExts = @("*.mp4", "*.mov", "*.mkv", "*.avi", "*.m4v")
$inputFiles = foreach ($ext in $videoExts) { Get-ChildItem -Path $InputDir -File -Filter $ext -ErrorAction SilentlyContinue }
$inputFiles = $inputFiles | Sort-Object FullName -Unique
if (-not $inputFiles -or $inputFiles.Count -eq 0) { throw "Input klasorunde video bulunamadi: $InputDir" }

$outputFiles = Get-ChildItem -Path $OutputDir -File -Filter "*.mp4" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime, Name
if (-not $outputFiles -or $outputFiles.Count -eq 0) { throw "Output klasorunde mp4 bulunamadi: $OutputDir" }

$pairs = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $inputFiles.Count; $i += 2) {
    $a = $inputFiles[$i]
    $b = if (($i + 1) -lt $inputFiles.Count) { $inputFiles[$i + 1] } else { $inputFiles[0] }
    $pairs.Add([pscustomobject]@{ A = $a; B = $b }) | Out-Null
}

$takeCount = [Math]::Min($pairs.Count, $outputFiles.Count)
$notesPath = Join-Path $OutputDir $NotesFileName

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Birlestirme Notlari") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Bu dosya, olusturulan cikti videolari icin kaynak link ve aciklama bilgisini listeler.") | Out-Null
$lines.Add("") | Out-Null

for ($i = 0; $i -lt $takeCount; $i++) {
    $out = $outputFiles[$i]
    $pair = $pairs[$i]
    $sourceA = Get-SourceVideoMetadata -VideoFile $pair.A
    $sourceB = Get-SourceVideoMetadata -VideoFile $pair.B

    $lines.Add("## $($out.Name)") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Kaynak Dosya | Link | Aciklama |") | Out-Null
    $lines.Add("| --- | --- | --- |") | Out-Null
    foreach ($src in @($sourceA, $sourceB)) {
        $safeName = Escape-MarkdownText (ConvertTo-SingleLineText $src.Name)
        $safeUrl = Escape-MarkdownText (ConvertTo-SingleLineText $src.Url)
        $safeDesc = Escape-MarkdownText (ConvertTo-SingleLineText $src.Description)
        if (-not $safeUrl) { $safeUrl = "-" }
        if (-not $safeDesc) { $safeDesc = "-" }
        $lines.Add("| $safeName | $safeUrl | $safeDesc |") | Out-Null
    }
    $lines.Add("") | Out-Null
}

[System.IO.File]::WriteAllLines($notesPath, $lines, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Olusturuldu: $notesPath"
Write-Host "Eslestirilen cikti sayisi: $takeCount"
