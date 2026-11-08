<#
.SYNOPSIS
    Records whatever the computer is playing (e.g. a browser tab) to an MP3 using ffmpeg.

.DESCRIPTION
    Needs ffmpeg and a loopback recording device (virtual-audio-capturer,
    Stereo Mix or VB-Cable). See the Setup section of README.md.

    By default it:
      - skips the silence before the audio starts (keeping 0.5 s of it), so the
        recording starts when the sound does
      - stops by itself after 1 second of silence, once the audio has started
    Press q in the window to stop recording at any time.

.EXAMPLE
    .\Record-ComputerAudio.ps1 -ListDevices

.EXAMPLE
    .\Record-ComputerAudio.ps1 -OutputFile recording.mp3

.EXAMPLE
    .\Record-ComputerAudio.ps1 -Device "CABLE Output (VB-Audio Virtual Cable)" -Duration 600

.EXAMPLE
    .\Record-ComputerAudio.ps1 -StopSilence 0      # don't stop on silence; record until q is pressed
.NOTES
    DISCLAIMER: Provided as-is, without warranty of any kind. Use at your own
    risk. Test on copies of your files first; the author accepts no
    responsibility for lost or damaged files or any other problems caused by
    running this script.
#>
param(
    # Recording device name. If omitted, the first virtual-audio-capturer / Stereo Mix / VB-Cable device found is used.
    [string] $Device,
    [string] $OutputFile = ("recording_{0:yyyyMMdd_HHmmss}.mp3" -f (Get-Date)),
    [string] $Bitrate = "320k",
    # Stop automatically after this many seconds. 0 = no time limit.
    [int] $Duration = 0,
    # Stop after this many seconds of silence (once the audio has started). 0 = don't stop on silence.
    [double] $StopSilence = 1,
    # How quiet the audio must be to count as silence.
    [string] $SilenceThreshold = "-30dB",
    # Keep all the silence before the audio starts instead of trimming it.
    [switch] $KeepLeadingSilence,
    [switch] $ListDevices
)

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    "ffmpeg was not found. Install it with: winget install Gyan.FFmpeg  (see the Setup section of README.md)"
    return
}

# Lists every DirectShow device ffmpeg can see, with its type. Older ffmpeg
# versions group devices under "audio"/"video" headings; newer ones put the type
# after each name, e.g. "Stereo Mix (Realtek(R) Audio)" (audio). Virtual devices
# are sometimes given a type other than audio, so auto-detection checks them all.
function Get-DshowDevices {
    $log = & ffmpeg -hide_banner -list_devices true -f dshow -i dummy 2>&1
    $section = ''
    foreach ($line in $log) {
        $l = "$line"
        if ($l -match 'DirectShow audio devices') { $section = 'audio'; continue }
        if ($l -match 'DirectShow video devices') { $section = 'video'; continue }
        if ($l -match 'Alternative name') { continue }
        if ($l -match '"([^"]+)"\s*(\(([^)]*)\))?') {
            $type = if ($Matches[3]) { $Matches[3] } else { $section }
            [pscustomobject]@{ Name = $Matches[1]; Type = $type }
        }
    }
}

function Show-Devices($list) {
    "Recording devices:"
    $list | Where-Object { $_.Type -match 'audio' } | ForEach-Object { "  $($_.Name)" }
    $other = @($list | Where-Object { $_.Type -notmatch 'audio' })
    if ($other) {
        "Other devices:"
        $other | ForEach-Object { "  $($_.Name)  ($($_.Type))" }
    }
}

$devices = @(Get-DshowDevices)

if ($ListDevices) {
    Show-Devices $devices
    return
}

if (-not $Device) {
    foreach ($pattern in 'virtual-audio-capturer', 'Stereo Mix', 'CABLE Output') {
        $Device = $devices | Where-Object { $_.Name -match $pattern } | Select-Object -First 1 -ExpandProperty Name
        if ($Device) { break }
    }
    if (-not $Device) {
        "No loopback device found. Install virtual-audio-capturer, enable Stereo Mix or install VB-Cable (see README.md), or pass -Device."
        Show-Devices $devices
        return
    }
}

$inv = [Globalization.CultureInfo]::InvariantCulture

$filters = @()
if (-not $KeepLeadingSilence) {
    $filters += "silenceremove=start_periods=1:start_silence=0.5:start_threshold=$SilenceThreshold"
}
if ($StopSilence -gt 0) {
    # Reports silence to this script, which then stops ffmpeg
    $filters += "silencedetect=noise=${SilenceThreshold}:d=$($StopSilence.ToString($inv))"
}

$ffArgs = @('-hide_banner', '-f', 'dshow', '-i', "audio=$Device")
if ($Duration -gt 0) { $ffArgs += @('-t', "$Duration") }
if ($filters) { $ffArgs += @('-af', ($filters -join ',')) }
$ffArgs += @('-c:a', 'libmp3lame', '-b:a', $Bitrate, '-y', $OutputFile)

"Recording from: $Device"
"Saving to:      $OutputFile"
if (-not $KeepLeadingSilence) { "Waiting for audio to start..." }
if ($StopSilence -gt 0) { "Stops after $StopSilence s of silence. Press q to stop sooner." }
else { "Press q to stop." }

if ($StopSilence -le 0) {
    & ffmpeg @ffArgs
    return
}

# Run ffmpeg with its output piped to this script, so the script can see the
# silence reports and send q to stop it.
$quoted = $ffArgs | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }
$psi = New-Object Diagnostics.ProcessStartInfo (Get-Command ffmpeg).Source
$psi.Arguments = $quoted -join ' '
$psi.UseShellExecute = $false
$psi.RedirectStandardError = $true
$psi.RedirectStandardInput = $true
$proc = [Diagnostics.Process]::Start($psi)

$stopping = $false
$progress = $false
$read = $proc.StandardError.ReadLineAsync()
while ($true) {
    if ($read.Wait(200)) {
        $line = $read.Result
        if ($null -eq $line) { break }
        if ($line -match '^\s*size=') {
            # Progress line: overwrite it in place
            Write-Host "`r$line" -NoNewline
            $progress = $true
        } elseif ($line -notmatch 'silencedetect') {
            if ($progress) { Write-Host ''; $progress = $false }
            Write-Host $line
        }
        if (-not $stopping -and $line -match 'silence_start') {
            if ($progress) { Write-Host ''; $progress = $false }
            Write-Host "$StopSilence s of silence - stopping."
            $proc.StandardInput.Write('q')
            $proc.StandardInput.Flush()
            $stopping = $true
        }
        $read = $proc.StandardError.ReadLineAsync()
    }
    # Pass q from the keyboard on to ffmpeg
    try {
        if (-not $stopping -and [Console]::KeyAvailable -and [Console]::ReadKey($true).KeyChar -eq 'q') {
            $proc.StandardInput.Write('q')
            $proc.StandardInput.Flush()
            $stopping = $true
        }
    } catch { }
}
$proc.WaitForExit()
if ($progress) { Write-Host '' }

if (Test-Path $OutputFile) {
    "Saved: $OutputFile"
}
