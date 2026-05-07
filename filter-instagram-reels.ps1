[CmdletBinding()]
param(
    [string]$CandidateLinksFile = ".\candidate-reels.txt",
    [string]$OutputLinksFile = ".\instagram-links.txt",
    [int]$MinViews = 10000,
    [int]$MinLikes = 0,
    [string]$CookiesFromBrowser = "chrome",
    [string]$ReportFile = ".\reels-filter-report.csv",
    [int]$TargetTotalCount = 0,
    [int]$MaxCandidatesToCheck = 30,
    [int]$MinDurationSec = 5,
    [int]$MinWidth = 480,
    [int]$MinHeight = 480,
    [int]$MinBitrateKbps = 250,
    [int]$MaxPerUploader = 2,
    [string]$BlacklistAccountsFile = ".\blacklist-accounts.txt",
    [string]$WhitelistAccountsFile = ".\whitelist-accounts.txt",
    [string]$BlacklistKeywordsFile = ".\blacklist-keywords.txt"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

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
        throw "$Name komutu bulunamadi."
    }
}

function Normalize-InstagramUrl {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    $trimmed = $Url.Trim()
    if ($trimmed -notmatch '^https?://(www\.)?instagram\.com/reel/[^/?#]+') {
        return $null
    }

    if ($trimmed -match '^(https?://(www\.)?instagram\.com/reel/[^/?#]+)') {
        return "$($Matches[1])/"
    }
    return $null
}

function Get-InstagramIdFromUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    if ($Url -match '^https?://(www\.)?instagram\.com/reel/([^/?#]+)/?') {
        return $Matches[2]
    }
    return $null
}

function Read-ListFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return (Get-Content -LiteralPath $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith("#") })
}

function Get-InstagramMeta {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [switch]$UseCookies
    )

    $baseArgs = @("--dump-single-json", "--skip-download", "--no-warnings")

    function Invoke-YtDlpQuiet {
        param([string[]]$Args)
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            return (& yt-dlp @Args 2>&1)
        } finally {
            $ErrorActionPreference = $prev
        }
    }

    if ($UseCookies -and -not [string]::IsNullOrWhiteSpace($CookiesFromBrowser)) {
        $argsWithCookies = $baseArgs + @("--cookies-from-browser", $CookiesFromBrowser, $Url)
        $jsonWithCookies = Invoke-YtDlpQuiet -Args $argsWithCookies
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($jsonWithCookies)) {
            return [pscustomobject]@{ json = $jsonWithCookies; mode = "with_cookies" }
        }
    }

    $argsNoCookies = $baseArgs + @($Url)
    $jsonNoCookies = Invoke-YtDlpQuiet -Args $argsNoCookies
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($jsonNoCookies)) {
        return [pscustomobject]@{ json = $jsonNoCookies; mode = "no_cookies" }
    }

    return $null
}

Get-ToolCommandOrThrow -Name "yt-dlp" -ExecutableName "yt-dlp.exe"

if (-not (Test-Path -LiteralPath $CandidateLinksFile)) {
    throw "Aday link dosyasi bulunamadi: $CandidateLinksFile"
}

$candidates = Get-Content -LiteralPath $CandidateLinksFile |
    ForEach-Object { Normalize-InstagramUrl -Url $_ } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique

if (-not $candidates -or $candidates.Count -eq 0) {
    throw "Aday dosyasinda gecerli Instagram Reel linki bulunamadi. Sadece /reel/ linkleri desteklenir."
}

$existing = @()
if (Test-Path -LiteralPath $OutputLinksFile) {
    $existing = Get-Content -LiteralPath $OutputLinksFile |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
}

$existingSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($link in $existing) {
    [void]$existingSet.Add($link)
}
$existingIdSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($link in $existing) {
    $id = Get-InstagramIdFromUrl -Url $link
    if (-not [string]::IsNullOrWhiteSpace($id)) { [void]$existingIdSet.Add($id) }
}

$blacklistAccounts = Read-ListFile -Path $BlacklistAccountsFile
$whitelistAccounts = Read-ListFile -Path $WhitelistAccountsFile
$blacklistKeywords = Read-ListFile -Path $BlacklistKeywordsFile

$blackAccSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($item in $blacklistAccounts) { [void]$blackAccSet.Add($item) }
$whiteAccSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($item in $whitelistAccounts) { [void]$whiteAccSet.Add($item) }

$acceptedPerUploader = @{}
$accepted = New-Object System.Collections.Generic.List[string]
$report = New-Object System.Collections.Generic.List[object]
$targetEnabled = $TargetTotalCount -gt 0
$useCookiesForAll = $false
if (-not [string]::IsNullOrWhiteSpace($CookiesFromBrowser) -and $candidates.Count -gt 0) {
    $probe = Get-InstagramMeta -Url $candidates[0] -UseCookies
    if ($probe -and $probe.mode -eq "with_cookies") {
        $useCookiesForAll = $true
    }
}

Write-Host "Toplam aday link: $($candidates.Count)"
Write-Host "Min izlenme filtresi: $MinViews"
if ($MinLikes -gt 0) { Write-Host "Min begeni filtresi: $MinLikes" }
if ($targetEnabled) {
    Write-Host "Hedef toplam link sayisi: $TargetTotalCount"
}

$checkedCount = 0
foreach ($url in $candidates) {
    if ($targetEnabled -and $existingSet.Count -ge $TargetTotalCount) {
        break
    }
    if ($MaxCandidatesToCheck -gt 0 -and $checkedCount -ge $MaxCandidatesToCheck) {
        Write-Host "Aday kontrol limiti doldu ($MaxCandidatesToCheck)."
        break
    }

    $candidateId = Get-InstagramIdFromUrl -Url $url
    if (-not [string]::IsNullOrWhiteSpace($candidateId) -and $existingIdSet.Contains($candidateId)) {
        $report.Add([pscustomobject]@{
            url = $url
            view_count = ""
            status = "already_exists"
            reason = "existing_id"
            source_mode = "skip_before_meta"
        }) | Out-Null
        continue
    }

    $checkedCount++
    Write-Host "Kontrol ediliyor: $url"

    $metaResult = Get-InstagramMeta -Url $url -UseCookies:([bool]$useCookiesForAll)
    if ($null -eq $metaResult) {
        $report.Add([pscustomobject]@{
            url = $url
            view_count = ""
            status = "error"
            reason = "yt_dlp_meta_failed"
        }) | Out-Null
        continue
    }

    $meta = $metaResult.json | ConvertFrom-Json
    $views = 0
    if ($null -ne $meta.view_count) {
        $views = [int64]$meta.view_count
    }
    $likes = 0
    if ($null -ne $meta.like_count) {
        $likes = [int64]$meta.like_count
    }
    $duration = 0
    if ($null -ne $meta.duration) { $duration = [double]$meta.duration }
    $width = 0
    if ($null -ne $meta.width) { $width = [int]$meta.width }
    $height = 0
    if ($null -ne $meta.height) { $height = [int]$meta.height }
    $bitrate = 0
    if ($null -ne $meta.tbr) { $bitrate = [double]$meta.tbr }
    elseif ($null -ne $meta.abr) { $bitrate = [double]$meta.abr }
    $uploader = ""
    if (-not [string]::IsNullOrWhiteSpace($meta.uploader)) { $uploader = "$($meta.uploader)".Trim() }
    elseif (-not [string]::IsNullOrWhiteSpace($meta.uploader_id)) { $uploader = "$($meta.uploader_id)".Trim() }

    $desc = ""
    if (-not [string]::IsNullOrWhiteSpace($meta.description)) { $desc = "$($meta.description)".ToLowerInvariant() }
    $title = ""
    if (-not [string]::IsNullOrWhiteSpace($meta.title)) { $title = "$($meta.title)".ToLowerInvariant() }

    $finalUrl = $meta.webpage_url
    if ([string]::IsNullOrWhiteSpace($finalUrl)) {
        $finalUrl = $url
    }
    $normalizedFinal = Normalize-InstagramUrl -Url $finalUrl
    if ([string]::IsNullOrWhiteSpace($normalizedFinal)) {
        $normalizedFinal = $url
    }

    $status = "accepted"
    $reason = ""
    if ($MinLikes -gt 0 -and $likes -lt $MinLikes) { $status = "below_threshold"; $reason = "like_count" }
    elseif ($views -lt $MinViews) { $status = "below_threshold"; $reason = "view_count" }
    elseif ($duration -lt $MinDurationSec) { $status = "filtered_quality"; $reason = "duration" }
    elseif ($width -lt $MinWidth -or $height -lt $MinHeight) { $status = "filtered_quality"; $reason = "resolution" }
    elseif ($bitrate -gt 0 -and $bitrate -lt $MinBitrateKbps) { $status = "filtered_quality"; $reason = "bitrate" }
    elseif (-not [string]::IsNullOrWhiteSpace($uploader) -and $blackAccSet.Contains($uploader)) { $status = "filtered_blacklist_account"; $reason = "blacklist_account" }
    else {
        foreach ($kw in $blacklistKeywords) {
            $k = $kw.ToLowerInvariant()
            if ($title.Contains($k) -or $desc.Contains($k)) {
                $status = "filtered_blacklist_keyword"
                $reason = "blacklist_keyword"
                break
            }
        }
    }

    if ($status -eq "accepted" -and -not [string]::IsNullOrWhiteSpace($uploader)) {
        if (-not $acceptedPerUploader.ContainsKey($uploader)) {
            $acceptedPerUploader[$uploader] = 0
        }
        $uploaderCount = [int]$acceptedPerUploader[$uploader]
        $uploaderWhitelisted = $whiteAccSet.Contains($uploader)
        if (-not $uploaderWhitelisted -and $uploaderCount -ge $MaxPerUploader) {
            $status = "filtered_diversity"
            $reason = "max_per_uploader"
        }
    }

    if ($status -eq "accepted") {
        if (-not $existingSet.Contains($normalizedFinal)) {
            [void]$existingSet.Add($normalizedFinal)
            $idFinal = Get-InstagramIdFromUrl -Url $normalizedFinal
            if (-not [string]::IsNullOrWhiteSpace($idFinal)) { [void]$existingIdSet.Add($idFinal) }
            $accepted.Add($normalizedFinal) | Out-Null
            if (-not [string]::IsNullOrWhiteSpace($uploader)) {
                if (-not $acceptedPerUploader.ContainsKey($uploader)) { $acceptedPerUploader[$uploader] = 0 }
                $acceptedPerUploader[$uploader] = [int]$acceptedPerUploader[$uploader] + 1
            }
        } else {
            $status = "already_exists"
            $reason = "existing_links_file"
        }
    }

    $report.Add([pscustomobject]@{
        url = $normalizedFinal
        view_count = $views
        like_count = $likes
        duration_sec = [Math]::Round($duration, 2)
        width = $width
        height = $height
        bitrate_kbps = [Math]::Round($bitrate, 2)
        uploader = $uploader
        status = $status
        reason = $reason
        source_mode = $metaResult.mode
    }) | Out-Null
}

if ($accepted.Count -gt 0) {
    Add-Content -LiteralPath $OutputLinksFile -Value ""
    Add-Content -LiteralPath $OutputLinksFile -Value ($accepted -join [Environment]::NewLine)
}

$report | Export-Csv -LiteralPath $ReportFile -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Filtre tamamlandi."
Write-Host "Eklenen yeni link sayisi: $($accepted.Count)"
Write-Host "Mevcut toplam link sayisi: $($existingSet.Count)"
Write-Host "Meta kontrol edilen aday: $checkedCount"
Write-Host "Rapor: $ReportFile"
