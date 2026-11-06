# ve-scripts

Scripts, prompts and helper tools for VideoExpress projects.

## Layout

| Folder | What goes in it |
|---|---|
| `projects/` | One folder per VideoExpress project. Copy `projects/_template` to start a new one. |
| `music/` | Music prompts and a running list of genres already used, so new tracks don't repeat old ones. |
| `tools/` | Helper scripts, e.g. splitting audio on silence. |

## Tools

- [`tools/Split-OnSilence.ps1`](tools/Split-OnSilence.ps1) — splits an MP3 into parts at silent gaps using ffmpeg.
