<#
.SYNOPSIS
    Records whatever the computer is playing (e.g. a browser tab) to an MP3 using ffmpeg.

.DESCRIPTION
    Needs a loopback recording device: enable "Stereo Mix" in Sound settings
    (Recording tab > right-click > Show Disabled Devices > Enable), or install
    a virtual device such as VB-Cable.

    Press q in the window to stop recording.

.EXAMPLE
    .\Record-ComputerAudio.ps1 -ListDevices

.EXAMPLE
    .\Record-ComputerAudio.ps1 -OutputFile recording.mp3

.EXAMPLE
    .\Record-ComputerAudio.ps1 -Device "CABLE Output (VB-Audio Virtual Cable)" -Duration 600
#>
param(
    # Recording device name. If omitted, the first Stereo Mix / VB-Cable / virtual-audio-capturer device found is used.
    [string] $Device,
    [string] $OutputFile = ("recording_{0:yyyyMMdd_HHmmss}.mp3" -f (Get-Date)),
    [string] $Bitrate = "192k",
    # Stop automatically after this many seconds. 0 = record until q is pressed.
    [int] $Duration = 0,
    [switch] $ListDevices
)

function Get-AudioDevices {
    $log = & ffmpeg -hide_banner -list_devices true -f dshow -i dummy 2>&1
    $inAudio = $false
    foreach ($line in $log) {
        $l = "$line"
        if ($l -match 'DirectShow audio devices') { $inAudio = $true; continue }
        if ($l -match 'DirectShow video devices') { $inAudio = $false; continue }
        if ($l -match 'Alternative name') { continue }
        if ($l -match '"([^"]+)"' -and ($inAudio -or $l -match '\(audio\)')) { $Matches[1] }
    }
}

$devices = @(Get-AudioDevices)

if ($ListDevices) {
    "Audio recording devices:"
    $devices | ForEach-Object { "  $_" }
    return
}

if (-not $Device) {
    $Device = $devices | Where-Object { $_ -match 'Stereo Mix|CABLE Output|virtual-audio-capturer' } | Select-Object -First 1
    if (-not $Device) {
        "No loopback device found. Enable Stereo Mix or install VB-Cable, or pass -Device."
        "Audio recording devices:"
        $devices | ForEach-Object { "  $_" }
        return
    }
}

"Recording from: $Device"
"Saving to:      $OutputFile"
"Press q to stop."

$ffArgs = @('-hide_banner', '-f', 'dshow', '-i', "audio=$Device")
if ($Duration -gt 0) { $ffArgs += @('-t', "$Duration") }
$ffArgs += @('-c:a', 'libmp3lame', '-b:a', $Bitrate, $OutputFile)
& ffmpeg @ffArgs
