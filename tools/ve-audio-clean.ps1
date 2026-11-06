<#
.SYNOPSIS
    Cleans the generated audio on VideoExpress clips: low rumble, crackle,
    broadband hum/hiss floor, and noise in the gaps between words.
    The video stream is copied untouched; only the audio is re-encoded.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ve-audio-clean.ps1 -Folder "C:\path\to\clips"
    powershell -ExecutionPolicy Bypass -File ve-audio-clean.ps1 -Folder "C:\path\to\clips" -Strength Strong
    powershell -ExecutionPolicy Bypass -File ve-audio-clean.ps1 -Folder "C:\path\to\clips" -AllStrengths

    -Strength      Light | Medium (default) | Strong
    -HumHz         50 or 60: also notch a steady mains-type hum and its first harmonics
    -Normalize     even out loudness across clips (-16 LUFS); dialogue clips only,
                   because on a clip with no speech it turns the leftover noise up
    -AllStrengths  write Light, Medium and Strong versions of every clip to compare by ear
#>
param(
    [Parameter(Mandatory = $true)][string]$Folder,
    [ValidateSet('Light', 'Medium', 'Strong')][string]$Strength = 'Medium',
    [ValidateSet(0, 50, 60)][int]$HumHz = 0,
    [switch]$Normalize,
    [switch]$AllStrengths
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host 'ffmpeg not found on PATH.' -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
    Write-Host "Folder not found: $Folder" -ForegroundColor Red
    exit 1
}

# Per-strength settings.
#   HighPass  removes the rumble below the voice, at 24 dB/octave (two stacked
#             12 dB filters). VE's rumble runs from 0 to about 150 Hz; Kurogane's
#             voice starts about 150 Hz. Measured on an A6 take: 120 Hz took the
#             gaps from -35 dB to -74 dB and left the speech level unchanged.
#   NoiseRed  afftdn noise reduction in dB; NoiseFloor its estimated floor in dB
#   GateRange how far the gate turns down the gaps between words (linear, 0.1 = -20 dB)
#   GateThr   gate threshold (linear, 0.015 = about -36 dB)
$presets = @{
    'Light'  = @{ HighPass = 100; NoiseRed = 8;  NoiseFloor = -40; GateRange = 0.25; GateThr = 0.010 }
    'Medium' = @{ HighPass = 120; NoiseRed = 12; NoiseFloor = -35; GateRange = 0.10; GateThr = 0.015 }
    'Strong' = @{ HighPass = 140; NoiseRed = 20; NoiseFloor = -30; GateRange = 0.03; GateThr = 0.025 }
}

function Get-FilterChain([string]$name) {
    $p = $presets[$name]
    $chain = @(
        "highpass=f=$($p.HighPass):poles=2",
        "highpass=f=$($p.HighPass):poles=2",
        'adeclick',
        "afftdn=nr=$($p.NoiseRed):nf=$($p.NoiseFloor):tn=1"
    )
    if ($HumHz -gt 0) {
        foreach ($k in 1, 2, 3) {
            $chain += "bandreject=f=$($HumHz * $k):width_type=q:width=30"
        }
    }
    $chain += "agate=threshold=$($p.GateThr):range=$($p.GateRange):attack=5:release=180"
    $chain += 'lowpass=f=14000'
    if ($Normalize) {
        $chain += 'loudnorm=I=-16:TP=-1.5:LRA=11'
    }
    return ($chain -join ',')
}

$outDir = Join-Path $Folder 'cleaned'
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

if ($AllStrengths) {
    $levels = @('Light', 'Medium', 'Strong')
} else {
    $levels = @($Strength)
}

$clips = Get-ChildItem -LiteralPath $Folder -File | Where-Object { $_.Extension -in '.mp4', '.mov', '.webm' }
if ($clips.Count -eq 0) {
    Write-Host "No .mp4, .mov or .webm files in $Folder" -ForegroundColor Yellow
    exit 0
}

$failed = 0
foreach ($clip in $clips) {
    foreach ($level in $levels) {
        $suffix = '_clean-' + $level.ToLower()
        if ($HumHz -gt 0) { $suffix += "-hum$HumHz" }
        $out = Join-Path $outDir ($clip.BaseName + $suffix + '.mp4')
        $af = Get-FilterChain $level

        Write-Host ("{0}  ->  {1}" -f $clip.Name, (Split-Path $out -Leaf))
        & ffmpeg -hide_banner -loglevel error -y -i $clip.FullName -map 0:v:0 -map 0:a:0? -c:v copy -af $af -c:a aac -b:a 192k -movflags +faststart $out
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   failed (ffmpeg exit $LASTEXITCODE)" -ForegroundColor Red
            $failed++
        }
    }
}

Write-Host ''
Write-Host "Done. Cleaned files are in $outDir" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "$failed file(s) failed." -ForegroundColor Red
    exit 1
}
