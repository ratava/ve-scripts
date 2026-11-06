<#
.SYNOPSIS
    Splits an MP3 into parts at silent gaps using ffmpeg.

.DESCRIPTION
    Needs ffmpeg. See the Setup section of README.md.

.EXAMPLE
    .\Split-OnSilence.ps1 -InputFile recording.mp3 -Noise -30dB -MinSilence 1
#>
param(
    [Parameter(Mandatory)] [string] $InputFile,
    # How quiet audio must be to count as silence. Raise (e.g. -25dB) if gaps are missed.
    [string] $Noise = "-30dB",
    # Minimum silence length in seconds. Lower it if short gaps are missed.
    [double] $MinSilence = 1,
    [string] $OutputPattern = "part_%03d.mp3"
)

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    "ffmpeg was not found. Install it with: winget install Gyan.FFmpeg  (see the Setup section of README.md)"
    return
}

$inv = [Globalization.CultureInfo]::InvariantCulture
$d = $MinSilence.ToString($inv)

# 1. Find silences and take the midpoint of each one as a cut point
$log = & ffmpeg -hide_banner -nostats -i $InputFile -af "silencedetect=noise=${Noise}:d=$d" -f null - 2>&1
$points = @()
foreach ($line in $log) {
    $l = "$line"
    if ($l -match 'silence_start:\s*(-?[\d.]+)') {
        $s = [double]::Parse($Matches[1], $inv)
    }
    elseif ($l -match 'silence_end:\s*([\d.]+)') {
        $e = [double]::Parse($Matches[1], $inv)
        $points += (($s + $e) / 2).ToString("0.000", $inv)
    }
}
$pts = $points -join ","
"Cut points: $pts"

# 2. Split at those points (no re-encoding)
if ($pts) {
    & ffmpeg -i $InputFile -f segment -segment_times $pts -c copy -reset_timestamps 1 $OutputPattern
} else {
    "No silences found - try a higher -Noise (e.g. -25dB) or a shorter -MinSilence"
}
