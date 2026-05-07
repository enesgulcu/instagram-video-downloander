[CmdletBinding()]
param(
    [string]$OutputFile = ".\candidate-reels.txt",
    [string]$ExistingLinksFile = ".\instagram-links.txt"
)

$ErrorActionPreference = "Stop"

function Get-ClipboardTextSafe {
    $txt = ""
    try { $txt = Get-Clipboard -Raw -ErrorAction SilentlyContinue } catch {}
    if (-not [string]::IsNullOrWhiteSpace($txt)) { return $txt }
    try {
        $arr = Get-Clipboard -ErrorAction SilentlyContinue
        if ($arr) { return ($arr -join [Environment]::NewLine) }
    } catch {}
    return ""
}

function Get-InstagramIdFromUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    if ($Url -match '^https?://(www\.)?instagram\.com/reel/([^/?#]+)/?') {
        return $Matches[2]
    }
    return $null
}

Write-Host ""
Write-Host "Chrome'da sonuc sayfasinda F12 > Console acin ve su kodu calistirin:"
Write-Host "copy([...document.querySelectorAll('a[href*=""/reel/""]')].map(a=>new URL(a.href,location.origin).href).filter((v,i,a)=>a.indexOf(v)===i).join('\n'));"
[void](Read-Host "Kodu calistirdiktan sonra Enter'a basin")

$clip = ""
for ($i = 0; $i -lt 3; $i++) {
    $clip = Get-ClipboardTextSafe
    if (-not [string]::IsNullOrWhiteSpace($clip)) { break }
    Start-Sleep -Milliseconds 600
}
if ([string]::IsNullOrWhiteSpace($clip)) {
    Write-Host "Panoda link bulunamadi. Manuel yapistirma moduna geciliyor."
    Write-Host "Linkleri buraya yapistir (her satir 1 link), bitince tek satira END yaz ve Enter'a bas."
    $manualLines = New-Object System.Collections.Generic.List[string]
    while ($true) {
        $line = Read-Host
        if ($line -eq "END") { break }
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $manualLines.Add($line) | Out-Null
        }
    }
    if ($manualLines.Count -eq 0) {
        throw "Ne panoda ne manuel giriste link bulunamadi."
    }
    $clip = ($manualLines -join [Environment]::NewLine)
}

$lines = $clip -split "(`r`n|`n|`r)" |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -match '^https?://(www\.)?instagram\.com/reel/' } |
    Sort-Object -Unique

if (-not $lines -or $lines.Count -eq 0) {
    throw "Panoda gecerli Instagram reel linki bulunamadi."
}

$existingIdSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
if (Test-Path -LiteralPath $ExistingLinksFile) {
    $existingLines = Get-Content -LiteralPath $ExistingLinksFile |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
    foreach ($ln in $existingLines) {
        $id = Get-InstagramIdFromUrl -Url $ln
        if (-not [string]::IsNullOrWhiteSpace($id)) { [void]$existingIdSet.Add($id) }
    }
}

$newLines = New-Object System.Collections.Generic.List[string]
foreach ($ln in $lines) {
    $id = Get-InstagramIdFromUrl -Url $ln
    if (-not [string]::IsNullOrWhiteSpace($id) -and -not $existingIdSet.Contains($id)) {
        $newLines.Add($ln) | Out-Null
    }
}

Set-Content -LiteralPath $OutputFile -Value (($newLines | Sort-Object -Unique) -join [Environment]::NewLine) -Encoding UTF8
Write-Host "Aday link dosyasi guncellendi: $OutputFile (toplam: $($lines.Count), yeni: $($newLines.Count))"
if ($newLines.Count -eq 0) {
    Write-Host "Uyari: Yeni reel bulunamadi. Daha fazla scroll yapip tekrar kopyalayin."
}
