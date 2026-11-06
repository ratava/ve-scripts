# ve-scripts

Helper scripts for working with VideoExpress media. The scripts are written for Windows PowerShell.

> **Disclaimer:** These scripts are provided as-is, without warranty of any kind. Use them at your own risk. Test on copies of your files first; the author accepts no responsibility for lost or damaged files or any other problems caused by running them.

## Scripts

- [`tools/ve-audio-clean.ps1`](tools/ve-audio-clean.ps1) — cleans the generated audio on VideoExpress clips (rumble, crackle, hiss, noise between words) without touching the video.
- [`tools/Record-ComputerAudio.ps1`](tools/Record-ComputerAudio.ps1) — records whatever the computer is playing (e.g. a browser tab) to an MP3 using ffmpeg.
- [`tools/Split-OnSilence.ps1`](tools/Split-OnSilence.ps1) — splits an MP3 into parts at silent gaps using ffmpeg.
- [`tools/Compress-ToSize.ps1`](tools/Compress-ToSize.ps1) — compresses a video to a target file size (e.g. to fit an upload limit).

## Setup

### 1. Install ffmpeg (needed by all the scripts)

Open PowerShell and run:

```powershell
winget install Gyan.FFmpeg
```

Close and reopen PowerShell, then check it works:

```powershell
ffmpeg -version
```

If you get "ffmpeg is not recognized", restart your computer. If it still isn't found, download a build from <https://www.gyan.dev/ffmpeg/builds/>, unzip it (e.g. to `C:\ffmpeg`) and add its `bin` folder (e.g. `C:\ffmpeg\bin`) to your `PATH`.

### 2. Install a loopback audio device (needed by Record-ComputerAudio.ps1)

Windows can't record what it is playing unless there is a recording device that captures it. Use **one** of these:

**Option A: virtual-audio-capturer (recommended)**

1. Go to <https://github.com/rdp/screen-capture-recorder-to-video-windows-free/releases>.
2. Download the latest `Setup.Screen.Capturer.Recorder.*.exe` and run it. It installs `virtual-audio-capturer`, which records whatever your default speakers are playing.
3. You don't need to change any sound settings. You keep hearing the audio while it records.

**Option B: Stereo Mix (built in on some PCs)**

1. Open **Control Panel > Sound** (or run `mmsys.cpl`), then the **Recording** tab.
2. Right-click in the list and tick **Show Disabled Devices**.
3. If **Stereo Mix** appears, right-click it and choose **Enable**. If it doesn't appear, your sound driver doesn't provide it; use option A or C.

**Option C: VB-Cable**

1. Download and install VB-Cable from <https://vb-audio.com/Cable/> (run the installer as administrator, then restart).
2. Set **CABLE Input** as your playback device, or set it as the output for just your browser in **Settings > System > Sound > Volume mixer**.
3. You won't hear that audio while it's routed to the cable unless you also turn on **Listen to this device** for **CABLE Output** (Sound > Recording > CABLE Output > Properties > Listen).

Check that the device shows up:

```powershell
.\tools\Record-ComputerAudio.ps1 -ListDevices
```

### 3. Allow the scripts to run

Windows blocks downloaded scripts by default. Run this once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

If a script still won't run, unblock it:

```powershell
Unblock-File .\tools\*.ps1
```

## Usage

### Record computer audio

```powershell
.\tools\Record-ComputerAudio.ps1                        # record until you press q
.\tools\Record-ComputerAudio.ps1 -OutputFile song.mp3   # choose the file name
.\tools\Record-ComputerAudio.ps1 -Duration 600          # stop by itself after 10 minutes
.\tools\Record-ComputerAudio.ps1 -Device "Stereo Mix (Realtek(R) Audio)"   # pick a device
```

Without `-Device`, it uses the first virtual-audio-capturer, Stereo Mix or VB-Cable device it finds. Recordings are saved as `recording_<date>_<time>.mp3` at 192 kbps unless you say otherwise.

### Split a recording on silence

```powershell
.\tools\Split-OnSilence.ps1 -InputFile recording.mp3
```

Parts are saved as `part_000.mp3`, `part_001.mp3`, and so on. It prints the cut points first.

If splits are missed:
- Lower `-MinSilence` (default `1` second), e.g. `-MinSilence 0.5`, for short gaps.
- Raise `-Noise` (default `-30dB`), e.g. `-Noise -25dB`, if the gaps have background hiss.

To see how loud a gap is (here, one second starting at 83 s):

```powershell
ffmpeg -hide_banner -ss 83 -t 1 -i recording.mp3 -af volumedetect -f null - 2>&1 | Select-String "mean_volume"
```

Set `-Noise` a few dB above the `mean_volume` it reports.

### Compress a video to a set size

```powershell
.\tools\Compress-ToSize.ps1 -InputFile clip.mp4 -TargetMB 25                  # fit in 25 MB
.\tools\Compress-ToSize.ps1 -InputFile clip.mp4 -TargetMB 8 -MaxHeight 720     # also scale down to 720p
```

The result is saved next to the original as `clip_25MB.mp4` unless you pass `-OutputFile`. It encodes the video twice (two-pass), so it takes a while, but the file ends up just under the target size.

If the result looks blocky, the target is too small for the video's length and resolution. Add `-MaxHeight 720` (or `480`), or lower the audio with `-AudioKbps 96`.

### Clean the audio on VideoExpress clips

```powershell
.\tools\ve-audio-clean.ps1 -Folder "C:\path\to\clips"                    # Medium strength
.\tools\ve-audio-clean.ps1 -Folder "C:\path\to\clips" -Strength Strong
.\tools\ve-audio-clean.ps1 -Folder "C:\path\to\clips" -AllStrengths      # Light, Medium and Strong versions to compare
.\tools\ve-audio-clean.ps1 -Folder "C:\path\to\clips" -HumHz 50          # also remove a steady 50 Hz hum
.\tools\ve-audio-clean.ps1 -Folder "C:\path\to\clips" -Normalize         # even out loudness (dialogue clips only)
```

It processes every `.mp4`, `.mov` and `.webm` in the folder and writes the results to a `cleaned` subfolder, named like `clip_clean-medium.mp4`. The video is copied as-is; only the audio is re-encoded.

- **Strength:** start with `-AllStrengths` on a few clips and pick the one that sounds best. `Strong` removes more noise but can make voices sound thin or cut off quiet word endings.
- **`-HumHz`:** only use it if there's a steady hum. Pick `50` or `60`, whichever matches the hum.
- **`-Normalize`:** only for clips with speech. On clips without speech it turns the leftover noise up.
