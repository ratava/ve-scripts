<#
.SYNOPSIS
    Compresses a video to a target file size using a two-pass ffmpeg encode.

.DESCRIPTION
    Works out the video bitrate needed to fit the target size from the
    video's length, then encodes it twice (H.264 + AAC) so the result lands
    close to, and just under, that size.

    Needs ffmpeg and ffprobe. See the Setup section of README.md.

.EXAMPLE
    .\Compress-ToSize.ps1 -InputFile clip.mp4 -TargetMB 25

.EXAMPLE
    .\Compress-ToSize.ps1 -InputFile clip.mp4 -TargetMB 8 -MaxHeight 720
.NOTES
    DISCLAIMER: Provided as-is, without warranty of any kind. Use at your own
    risk. Test on copies of your files first; the author accepts no
    responsibility for lost or damaged files or any other problems caused by
    running this script.
#>
param(
    [Parameter(Mandatory)] [string] $InputFile,
    # Target size in megabytes (MiB, as Windows Explorer shows them).
    [Parameter(Mandatory)] [double] $TargetMB,
    [string] $OutputFile,
    [int] $AudioKbps = 128,
    # Scale the video down to at most this height (e.g. 720). 0 = keep original size.
    [int] $MaxHeight = 0,
    # Slower presets give better quality for the same size.
    [string] $Preset = "slow"
)

foreach ($tool in 'ffmpeg', 'ffprobe') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        "$tool was not found. Install it with: winget install Gyan.FFmpeg  (see the Setup section of README.md)"
        return
    }
}

$inv = [Globalization.CultureInfo]::InvariantCulture

if (-not $OutputFile) {
    $base = [IO.Path]::GetFileNameWithoutExtension($InputFile)
    $dir = Split-Path -Parent (Resolve-Path $InputFile)
    $OutputFile = Join-Path $dir ("{0}_{1}MB.mp4" -f $base, $TargetMB.ToString($inv))
}

$durText = & ffprobe -v error -show_entries format=duration -of csv=p=0 $InputFile
$duration = [double]::Parse("$durText".Trim(), $inv)

# Total kbit available, less ~2% for container overhead, less the audio
$totalKbit = $TargetMB * 8192 * 0.98
$videoKbps = [math]::Floor($totalKbit / $duration - $AudioKbps)

"Length:        {0:0.0} s" -f $duration
"Target size:   $TargetMB MB"
"Video bitrate: $videoKbps kbps   Audio: $AudioKbps kbps"

if ($videoKbps -lt 100) {
    "That leaves too little bitrate for the video. Raise -TargetMB, lower -AudioKbps or use a shorter clip."
    return
}
if ($videoKbps -lt 1000 -and $MaxHeight -eq 0) {
    "Tip: at this bitrate the video may look blocky. Try -MaxHeight 720 or -MaxHeight 480."
}

$vf = @()
if ($MaxHeight -gt 0) { $vf = @('-vf', "scale=-2:'min($MaxHeight,ih)'") }

$passLog = Join-Path $env:TEMP "ffmpeg2pass_$PID"
$common = @('-hide_banner', '-y', '-i', $InputFile) + $vf + @(
    '-c:v', 'libx264', '-preset', $Preset, '-b:v', "${videoKbps}k", '-passlogfile', $passLog)

"Pass 1 of 2..."
& ffmpeg @common -pass 1 -an -f null NUL
"Pass 2 of 2..."
& ffmpeg @common -pass 2 -c:a aac -b:a "${AudioKbps}k" -movflags +faststart $OutputFile

Remove-Item "$passLog*" -ErrorAction SilentlyContinue

if (Test-Path $OutputFile) {
    "Done: $OutputFile ({0:0.00} MB)" -f ((Get-Item $OutputFile).Length / 1MB)
}
