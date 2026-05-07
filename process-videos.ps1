[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [string]$BgmFile = "",

    [double]$CutSeconds = 5.0,
    [double]$BgmVolume = 0.08,
    [double]$Contrast = 1.28,
    [double]$Saturation = 1.35,
    [double]$Brightness = 0.04,
    [double]$AudioGainDb = 3.5,
    [string]$Watermark = "evitemiz.com",
    [string]$FontFile = "C:\Windows\Fonts\segoeui.ttf",
    [ValidateSet("libx264","h264_nvenc")]
    [string]$VideoEncoder = "libx264",
    [string]$EncodePreset = "medium",
    [int]$Crf = 20,
    [int]$MaxRetry = 2,
    [string]$ProcessReportFile = ".\process-report.csv",
    [int]$ParallelWorkers = 1,
    [switch]$SingleMode,
    [string]$SingleFileA = "",
    [string]$SingleFileB = "",
    [string]$SingleOutFile = "",
    [int]$SinglePairIndex = 0
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

function Invoke-FFmpegOrThrow {
    param([string[]]$FfmpegArgs)
    $attempt = 0
    do {
        $attempt++
        & ffmpeg @FfmpegArgs
        if ($LASTEXITCODE -eq 0) {
            return
        }
        Start-Sleep -Seconds ([Math]::Min(8, $attempt * 2))
    } while ($attempt -lt $MaxRetry)
    throw "ffmpeg komutu basarisiz oldu: $($FfmpegArgs -join ' ')"
}

function Get-VideoCodecArgs {
    if ($VideoEncoder -eq "h264_nvenc") {
        return @("-c:v", "h264_nvenc", "-cq", "$Crf", "-preset", "$EncodePreset", "-rc", "vbr_hq")
    }
    return @("-c:v", "libx264", "-crf", "$Crf", "-preset", "$EncodePreset")
}

function Add-ProcessLog {
    param(
        [string]$InputA,
        [string]$InputB,
        [string]$Output,
        [string]$Status,
        [string]$ErrorMessage = ""
    )
    $row = [pscustomobject]@{
        date          = (Get-Date).ToString("s")
        input_a       = $InputA
        input_b       = $InputB
        output        = $Output
        status        = $Status
        error         = $ErrorMessage
    }
    $reportFull = [System.IO.Path]::GetFullPath($ProcessReportFile)
    $parent = Split-Path -LiteralPath $reportFull -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hashHex = [BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($reportFull))) -replace '-'
    $mtx = New-Object System.Threading.Mutex($false, "Local\FFmpegProcessReport_$($hashHex.Substring(0, 48))")
    if (-not $mtx.WaitOne(120000)) {
        throw "Process raporu yazilamadi (dosya beklemesi zaman asimi): $reportFull"
    }
    try {
        $row | Export-Csv -LiteralPath $reportFull -NoTypeInformation -Append -Encoding UTF8
    } finally {
        [void]$mtx.ReleaseMutex()
        $mtx.Dispose()
    }
}

function Format-ConcatListPath([string]$Path) {
    $norm = ($Path.Trim() -replace '\\', '/')
    $escaped = $norm.Replace("'", "'\''")
    return "'$escaped'"
}

function Invoke-PairProcess {
    param(
        [System.IO.FileInfo]$FileA,
        [System.IO.FileInfo]$FileB,
        [string]$OutFile,
        [string]$TempDir,
        [int]$PairIndex
    )
    try {
        $pairTag = "pair-$PairIndex"
        $tailA = Join-Path $TempDir "$pairTag-a-tail.mp4"
        $fullA = Join-Path $TempDir "$pairTag-a-full.mp4"
        $tailB = Join-Path $TempDir "$pairTag-b-tail.mp4"
        $fullB = Join-Path $TempDir "$pairTag-b-full.mp4"
        $list = Join-Path $TempDir "$pairTag-list.txt"

        Write-Host "-> Isleniyor: $($FileA.Name) + $($FileB.Name)"

        $durationA = Get-VideoDurationSeconds -Path $FileA.FullName
        $cutA = [Math]::Min([Math]::Max($CutSeconds, 0.1), [Math]::Max($durationA - 0.1, 0.1))
        $startA = [Math]::Max(0.0, $durationA - $cutA)

        $codecArgs = Get-VideoCodecArgs
        # Concat demuxer stabilitesi icin tum ara segmentleri tek bir teknik profile normalize et.
        $normVf = "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,fps=30,format=yuv420p"
        $normAudioArgs = @("-ar", "48000", "-ac", "2")

        $ffArgs = @("-y", "-ss", "$startA", "-i", "$($FileA.FullName)", "-t", "$cutA", "-vf", "$normVf") + $codecArgs + @("-c:a", "aac", "-b:a", "128k") + $normAudioArgs + @("$tailA")
        Invoke-FFmpegOrThrow -FfmpegArgs $ffArgs
        $ffArgs = @("-y", "-i", "$($FileA.FullName)", "-vf", "$normVf") + $codecArgs + @("-c:a", "aac", "-b:a", "128k") + $normAudioArgs + @("$fullA")
        Invoke-FFmpegOrThrow -FfmpegArgs $ffArgs

        $durationB = Get-VideoDurationSeconds -Path $FileB.FullName
        $cutB = [Math]::Min([Math]::Max($CutSeconds, 0.1), [Math]::Max($durationB - 0.1, 0.1))
        $startB = [Math]::Max(0.0, $durationB - $cutB)

        $ffArgs = @("-y", "-ss", "$startB", "-i", "$($FileB.FullName)", "-t", "$cutB", "-vf", "$normVf") + $codecArgs + @("-c:a", "aac", "-b:a", "128k") + $normAudioArgs + @("$tailB")
        Invoke-FFmpegOrThrow -FfmpegArgs $ffArgs
        $ffArgs = @("-y", "-i", "$($FileB.FullName)", "-vf", "$normVf") + $codecArgs + @("-c:a", "aac", "-b:a", "128k") + $normAudioArgs + @("$fullB")
        Invoke-FFmpegOrThrow -FfmpegArgs $ffArgs

        # Unicode yollari koru, fakat concat demuxer satirin basinda BOM kabul etmez.
        $concatText = @(
            "file $(Format-ConcatListPath $tailA)"
            "file $(Format-ConcatListPath $fullA)"
            "file $(Format-ConcatListPath $tailB)"
            "file $(Format-ConcatListPath $fullB)"
        ) -join "`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($list, $concatText + "`n", $utf8NoBom)

        $drawText = "drawtext=text='$Watermark':x=(w-tw)/2:y=h*0.77-th/2:fontsize=h*0.0225:fontcolor=white@0.98:borderw=1.2:bordercolor=black@0.25:box=1:boxcolor=black@0.70:boxborderw=14:shadowcolor=black@0.20:shadowx=1:shadowy=1"
        if (-not [string]::IsNullOrWhiteSpace($FontFile) -and (Test-Path -LiteralPath $FontFile)) {
            $fontFilterPath = $FontFile.Replace("\", "/").Replace(":", "\:")
            $drawText = "drawtext=fontfile='$fontFilterPath':text='$Watermark':x=(w-tw)/2:y=h*0.77-th/2:fontsize=h*0.0225:fontcolor=white@0.98:borderw=1.2:bordercolor=black@0.25:box=1:boxcolor=black@0.70:boxborderw=14:shadowcolor=black@0.20:shadowx=1:shadowy=1"
        }
        $videoFilter = "eq=contrast=$($Contrast):saturation=$($Saturation):brightness=$($Brightness),$drawText"
        $hasAudio = (Test-AudioStreamExists -Path $FileA.FullName) -or (Test-AudioStreamExists -Path $FileB.FullName)
        $concatInputArgs = @("-f", "concat", "-safe", "0", "-i", "$list")
        $seoMetadataArgs = @(
            "-metadata", "title=evitemiz.com | Ev Temizligi Pratikleri",
            "-metadata", "artist=evitemiz.com",
            "-metadata", "album=evitemiz.com video serisi",
            "-metadata", "genre=Ev Temizligi",
            "-metadata", "comment=evitemiz.com - ev temizligi, pratik temizlik onerileri",
            "-metadata", "description=Ev temizligi, pratik temizlik, duzen ve hijyen ipuclari | evitemiz.com",
            "-metadata", "synopsis=Ev temizligi icerikleri | evitemiz.com",
            "-metadata", "keywords=evitemiz.com,ev temizligi,temizlik,pratik temizlik,ev duzeni,hijyen"
        )

        if ($useBgm -and $hasAudio) {
            $fc = "[0:v]$videoFilter[v];[0:a]volume=${AudioGainDb}dB[a0];[1:a]volume=$BgmVolume[a1];[a0][a1]amix=inputs=2:duration=first:dropout_transition=2[a]"
            $ffArgs = @("-y") + $concatInputArgs + @(
                "-stream_loop", "-1", "-i", "$BgmFile",
                "-filter_complex", "$fc",
                "-map", "[v]", "-map", "[a]",
                "-r", "30"
            ) + $codecArgs + @(
                "-c:a", "aac", "-b:a", "160k"
            )
            $ffArgs += $seoMetadataArgs
            $ffArgs += @("-shortest", "$OutFile")
            Invoke-FFmpegOrThrow -FfmpegArgs $ffArgs
        }
        elseif ($useBgm -and -not $hasAudio) {
            $fc = "[0:v]$videoFilter[v];[1:a]volume=$BgmVolume[a]"
            $ffArgs = @("-y") + $concatInputArgs + @(
                "-stream_loop", "-1", "-i", "$BgmFile",
                "-filter_complex", "$fc",
                "-map", "[v]", "-map", "[a]",
                "-r", "30"
            ) + $codecArgs + @(
                "-c:a", "aac", "-b:a", "160k"
            )
            $ffArgs += $seoMetadataArgs
            $ffArgs += @("-shortest", "$OutFile")
            Invoke-FFmpegOrThrow -FfmpegArgs $ffArgs
        } else {
            if ($hasAudio) {
                $fc = "[0:v]$videoFilter[v]"
                $ffArgs = @("-y") + $concatInputArgs + @(
                    "-filter_complex", "$fc",
                    "-map", "[v]", "-map", "0:a",
                    "-r", "30"
                ) + $codecArgs + @(
                    "-filter:a", "volume=${AudioGainDb}dB",
                    "-c:a", "aac", "-b:a", "160k"
                )
                $ffArgs += $seoMetadataArgs
                $ffArgs += @("$OutFile")
                Invoke-FFmpegOrThrow -FfmpegArgs $ffArgs
            } else {
                $fc = "[0:v]$videoFilter[v]"
                $ffArgs = @("-y") + $concatInputArgs + @(
                    "-filter_complex", "$fc",
                    "-map", "[v]",
                    "-r", "30"
                ) + $codecArgs + @(
                    "-an"
                )
                $ffArgs += $seoMetadataArgs
                $ffArgs += @("$OutFile")
                Invoke-FFmpegOrThrow -FfmpegArgs $ffArgs
            }
        }

        Add-ProcessLog -InputA $FileA.Name -InputB $FileB.Name -Output $OutFile -Status "success"
        Write-Host "   Tamamlandi: $OutFile"
    }
    catch {
        Add-ProcessLog -InputA $FileA.Name -InputB $FileB.Name -Output $OutFile -Status "error" -ErrorMessage $_.Exception.Message
        throw
    }
}

function Get-VideoDurationSeconds {
    param([string]$Path)
    $duration = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$Path"
    if ($LASTEXITCODE -ne 0 -or -not $duration) {
        throw "Video suresi okunamadi: $Path"
    }
    return [double]$duration
}

function Test-AudioStreamExists {
    param([string]$Path)
    $result = & ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 "$Path"
    return ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($result))
}

function New-RandomCode {
    param([int]$Length = 5)
    $chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".ToCharArray()
    return -join (1..$Length | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
}

function Test-NvencRuntimeEncodeWorks {
    param([Parameter(Mandatory = $true)][string]$ProbeFile)
    $ffArgs = @(
        "-y", "-hide_banner", "-loglevel", "error",
        "-f", "lavfi", "-i", "color=c=black:s=640x360:d=0.10",
        "-c:v", "h264_nvenc", "-preset", "fast",
        "-f", "mp4", "$ProbeFile"
    )
    $prevNativeErrPref = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        & ffmpeg @ffArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        return (Test-Path -LiteralPath $ProbeFile)
    } catch {
        return $false
    } finally {
        $PSNativeCommandUseErrorActionPreference = $prevNativeErrPref
    }
}

Get-ToolCommandOrThrow -Name "ffmpeg" -ExecutableName "ffmpeg.exe"
Get-ToolCommandOrThrow -Name "ffprobe" -ExecutableName "ffprobe.exe"

# Encoder listede olsa bile (surucu/VM/headless) NVENC bazen calismaz; tum isi dusurmek yerine CPU'ya dus.
if ($VideoEncoder -eq "h264_nvenc") {
    $nvencProbe = Join-Path ([System.IO.Path]::GetTempPath()) "ffmpeg-nvenc-probe-$PID.mp4"
    try {
        if (-not (Test-NvencRuntimeEncodeWorks -ProbeFile $nvencProbe)) {
            Write-Host "NVENC bu sistemde kullanilamadi; kodlama libx264 (CPU) ile surdurulecek."
            $VideoEncoder = "libx264"
            if ($EncodePreset -match '^p\d+$') { $EncodePreset = "medium" }
        }
    } finally {
        Remove-Item -LiteralPath $nvencProbe -Force -ErrorAction SilentlyContinue
    }
}

if (-not [System.IO.Path]::IsPathRooted($InputDir)) {
    $InputDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $InputDir))
}
if (-not [System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputDir))
}
if (-not [string]::IsNullOrWhiteSpace($BgmFile) -and -not [System.IO.Path]::IsPathRooted($BgmFile)) {
    $BgmFile = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $BgmFile))
}

if (-not (Test-Path -LiteralPath $InputDir)) {
    throw "Input klasoru bulunamadi: $InputDir"
}
$useBgm = $false
if (-not [string]::IsNullOrWhiteSpace($BgmFile)) {
    if (-not (Test-Path -LiteralPath $BgmFile)) {
        throw "BGM dosyasi bulunamadi: $BgmFile"
    }
    $useBgm = $true
}

if ($SingleMode) {
    if (-not (Test-Path -LiteralPath $SingleFileA)) { throw "SingleFileA bulunamadi: $SingleFileA" }
    if (-not (Test-Path -LiteralPath $SingleFileB)) { throw "SingleFileB bulunamadi: $SingleFileB" }
    if ([string]::IsNullOrWhiteSpace($SingleOutFile)) { throw "SingleOutFile bos olamaz." }

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $singleTempRoot = Join-Path $OutputDir ".temp_work"
    New-Item -ItemType Directory -Force -Path $singleTempRoot | Out-Null
    $singleTempDir = Join-Path $singleTempRoot "job-$SinglePairIndex"
    New-Item -ItemType Directory -Force -Path $singleTempDir | Out-Null

    $sfA = Get-Item -LiteralPath $SingleFileA
    $sfB = Get-Item -LiteralPath $SingleFileB
    Invoke-PairProcess -FileA $sfA -FileB $sfB -OutFile $SingleOutFile -TempDir $singleTempDir -PairIndex $SinglePairIndex
    Remove-Item -Path $singleTempDir -Recurse -Force -ErrorAction SilentlyContinue
    return
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$tempDir = Join-Path $OutputDir ".temp_work"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
Get-ChildItem -Path $OutputDir -File -Filter "*.mp4" -ErrorAction SilentlyContinue | Remove-Item -Force

$videoExts = @("*.mp4", "*.mov", "*.mkv", "*.avi", "*.m4v")
$files = foreach ($ext in $videoExts) { Get-ChildItem -Path $InputDir -File -Filter $ext }
$files = $files | Sort-Object FullName -Unique

if (-not $files) {
    throw "Input klasorunde video bulunamadi: $InputDir"
}

if ($ParallelWorkers -lt 1) { $ParallelWorkers = 1 }

Write-Host "Bulunan video sayisi: $($files.Count)"
Write-Host "Paralel worker sayisi: $ParallelWorkers"
Write-Host "Islem basliyor..."

$pairs = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $files.Count; $i += 2) {
    $fileA = $files[$i]
    $fileB = if (($i + 1) -lt $files.Count) { $files[$i + 1] } else { $files[0] }
    do {
        $randomCode = New-RandomCode -Length 5
        $outFile = Join-Path $OutputDir "evitemiz.com_$randomCode.mp4"
    } while (Test-Path -LiteralPath $outFile)
    $pairs.Add([pscustomobject]@{ PairIndex = $i; FileA = $fileA; FileB = $fileB; OutFile = $outFile }) | Out-Null
}

$failedCount = 0
if ($ParallelWorkers -gt 1) {
    Write-Warning "Stabilite icin paralel isleme devre disi birakildi; ciftler sirali islenecek."
}
foreach ($pair in $pairs) {
    try {
        Invoke-PairProcess -FileA $pair.FileA -FileB $pair.FileB -OutFile $pair.OutFile -TempDir $tempDir -PairIndex $pair.PairIndex
    } catch {
        $failedCount++
        Write-Warning "Cift isleme hatasi (atlanan): $($pair.FileA.Name) + $($pair.FileB.Name). Ayrinti: $ProcessReportFile"
    }
}
if ($failedCount -gt 0) {
    Write-Warning "Toplam $failedCount cift hatali/atlanmis durumda."
}

Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "Tum videolar basariyla islendi."
