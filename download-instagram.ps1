[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$UrlListFile,

    [string]$OutputDir = ".\input",
    [string]$CookiesFile = "",
    [switch]$SkipIfExists,
    [int]$MaxRetry = 3,
    [string]$DownloadReportFile = ".\download-report.csv"
)

$ErrorActionPreference = "Stop"

function Get-ToolCommandOrThrow {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$ExecutableName
    )

    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        return
    }

    $pkgRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $pkgRoot) {
        $foundExe = Get-ChildItem -Path $pkgRoot -Recurse -Filter $ExecutableName -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if ($foundExe) {
            $toolDir = Split-Path -Path $foundExe -Parent
            $env:Path = "$toolDir;$env:Path"
        }
    }

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name komutu bulunamadi. Lutfen once kurulum adimini calistirin."
    }
}

function Sync-ArchiveFromExistingFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetDir,
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath
    )

    if (-not (Test-Path -LiteralPath $ArchivePath)) {
        New-Item -ItemType File -Path $ArchivePath -Force | Out-Null
    }

    $existingLines = Get-Content -LiteralPath $ArchivePath -ErrorAction SilentlyContinue
    $archiveSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in $existingLines) {
        $trim = $line.Trim()
        if ($trim) {
            [void]$archiveSet.Add($trim)
        }
    }

    $videoExts = @("*.mp4", "*.mov", "*.mkv", "*.avi", "*.m4v", "*.webm")
    $files = foreach ($ext in $videoExts) {
        Get-ChildItem -Path $TargetDir -File -Filter $ext -ErrorAction SilentlyContinue
    }

    $added = 0
    foreach ($file in ($files | Sort-Object FullName -Unique)) {
        # Dosya formati: %(uploader)s_%(id)s.%(ext)s -> sondaki "_" sonrasi ID
        $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $lastUnderscore = $name.LastIndexOf("_")
        if ($lastUnderscore -lt 0 -or $lastUnderscore -ge ($name.Length - 1)) {
            continue
        }

        $id = $name.Substring($lastUnderscore + 1)
        if ($id -notmatch '^[A-Za-z0-9_-]{5,}$') {
            continue
        }

        $entry = "instagram $id"
        if (-not $archiveSet.Contains($entry)) {
            Add-Content -LiteralPath $ArchivePath -Value $entry
            [void]$archiveSet.Add($entry)
            $added++
        }
    }

    if ($added -gt 0) {
        Write-Host "Arsiv log guncellendi: $added kayit eklendi."
    }
}

function Get-ArchiveEntrySet {
    param([Parameter(Mandatory = $true)][string]$ArchivePath)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if (-not (Test-Path -LiteralPath $ArchivePath)) {
        return (, $set)
    }
    foreach ($line in (Get-Content -LiteralPath $ArchivePath -ErrorAction SilentlyContinue)) {
        $trim = $line.Trim()
        if ($trim) { [void]$set.Add($trim) }
    }
    return (, $set)
}

function Get-InstagramIdFromUrl {
    param([Parameter(Mandatory = $true)][string]$Url)
    $m = [regex]::Match($Url, '(?i)instagram\.com/(?:reel|reels|p)/([A-Za-z0-9_-]+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function Get-DownloadUrlVariants {
    param([Parameter(Mandatory = $true)][string]$Url)
    $items = New-Object System.Collections.Generic.List[string]
    $items.Add($Url) | Out-Null
    $id = Get-InstagramIdFromUrl -Url $Url
    if (-not [string]::IsNullOrWhiteSpace($id)) {
        foreach ($u in @(
            "https://www.instagram.com/reel/$id/",
            "https://www.instagram.com/reels/$id/",
            "https://www.instagram.com/p/$id/"
        )) {
            if (-not ($items -contains $u)) {
                $items.Add($u) | Out-Null
            }
        }
    }
    return (, $items)
}

Get-ToolCommandOrThrow -Name "yt-dlp" -ExecutableName "yt-dlp.exe"

if (-not (Test-Path -LiteralPath $UrlListFile)) {
    throw "Link dosyasi bulunamadi: $UrlListFile"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$urls = Get-Content -LiteralPath $UrlListFile |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") }

if (-not $urls) {
    throw "Link dosyasinda gecerli URL yok."
}

$archiveFile = Join-Path $OutputDir "downloaded-archive.txt"
Sync-ArchiveFromExistingFiles -TargetDir $OutputDir -ArchivePath $archiveFile
$archiveEntries = Get-ArchiveEntrySet -ArchivePath $archiveFile

$baseArgs = @(
    "--ignore-errors",
    "--no-warnings",
    "--restrict-filenames",
    "--no-playlist",
    "--merge-output-format", "mp4",
    "--add-metadata",
    "--download-archive", "$archiveFile",
    "-o", (Join-Path $OutputDir "%(uploader)s_%(id)s.%(ext)s")
)

if ($SkipIfExists) {
    $baseArgs += "--no-overwrites"
}

if ($CookiesFile -and (Test-Path -LiteralPath $CookiesFile)) {
    $baseArgs += @("--cookies", "$CookiesFile")
}

Write-Host "Indirilecek link sayisi: $($urls.Count)"
foreach ($url in $urls) {
    $ok = $false
    $err = ""
    $status = "error"
    $igId = Get-InstagramIdFromUrl -Url $url
    if ($igId) {
        $archiveKey = "instagram $igId"
        if ($archiveEntries.Contains($archiveKey)) {
            $status = "already_downloaded"
            $ok = $true
            $err = "Daha once bu icerik indirildi/paylasildi; tekrar indirilmedi."
            Write-Warning "Atlandi: $url -> Daha once bu icerik indirildi/paylasildi, tekrar indirilmedi."
            [pscustomobject]@{
                date = (Get-Date).ToString("s")
                url = $url
                status = $status
                retries = 0
                error = $err
            } | Export-Csv -LiteralPath $DownloadReportFile -NoTypeInformation -Append -Encoding UTF8
            continue
        }
    }
    $attempt = 0
    $variants = Get-DownloadUrlVariants -Url $url
    do {
        $attempt++
        Write-Host "-> Indiriliyor: $url (deneme $attempt/$MaxRetry)"
        $nativeExit = 1
        $output = @()
        foreach ($candidateUrl in $variants) {
            if ($candidateUrl -ne $url) {
                Write-Host "   Alternatif URL deneniyor: $candidateUrl"
            }
            try {
                # Farkli PowerShell surumlerinde native stderr davranisi degisiyor; exception'i yutup exit code ile yonet.
                $output = & yt-dlp @baseArgs "$candidateUrl" 2>&1
                $nativeExit = $LASTEXITCODE
            } catch {
                $nativeExit = if ($LASTEXITCODE -ne $null) { [int]$LASTEXITCODE } else { 1 }
                $output = @($_.Exception.Message)
            }
            if ($nativeExit -eq 0) { break }
        }
        if ($nativeExit -eq 0) {
            $ok = $true
            $status = "downloaded_or_skipped"
            if ($igId) {
                [void]$archiveEntries.Add("instagram $igId")
            }
            break
        }
        $err = ($output | Select-Object -Last 1)
        Start-Sleep -Seconds ([Math]::Min(10, $attempt * 2))
    } while ($attempt -lt $MaxRetry)
    if (-not $ok) { $status = "error" }

    [pscustomobject]@{
        date = (Get-Date).ToString("s")
        url = $url
        status = $status
        retries = $attempt
        error = $err
    } | Export-Csv -LiteralPath $DownloadReportFile -NoTypeInformation -Append -Encoding UTF8
}

$failedCount = (Import-Csv -LiteralPath $DownloadReportFile | Where-Object { $_.status -eq "error" }).Count
if ($failedCount -gt 0) { Write-Warning "Bazi linklerde indirme hatasi oldu. Rapor: $DownloadReportFile" }

Write-Host ""
Write-Host "Indirme adimi tamamlandi. Videolar: $OutputDir"
