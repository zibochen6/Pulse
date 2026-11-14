# Pulse 0.1.8 — demonstration assets

These assets demonstrate the interface introduced in Pulse 0.1.8.
They were captured before the release version bump; interface behavior is unchanged.
All account values and task text are synthetic and labelled as demo data.

| Preview | English | 简体中文 |
| --- | --- | --- |
| Home · light | [PNG](home-en-light.png) | [PNG](home-zh-Hans-light.png) |
| Home · dark | [PNG](home-en-dark.png) | [PNG](home-zh-Hans-dark.png) |
| Settings · light | [PNG](settings-en-light.png) | [PNG](settings-zh-Hans-light.png) |
| Settings · dark | [PNG](settings-en-dark.png) | [PNG](settings-zh-Hans-dark.png) |
| 18-second demonstration | [MP4](pulse-demo-en.mp4) · [GIF](pulse-demo-en.gif) | [MP4](pulse-demo-zh-Hans.mp4) · [GIF](pulse-demo-zh-Hans.gif) |

The exporter mounts the actual SwiftUI product views in native hosting windows.
Scripted actions invoke the actual task and presentation controllers against a
temporary store: add/complete a task, switch lists, search tags, inspect usage
and open Settings. It captures 540 frames at 30 fps and encodes an 18-second MP4.
This is a reproducible product-view demonstration, not proof of mouse delivery,
native menu-bar dismissal, Chinese IME or measured interactive frame rate.

Regenerate from the repository root with `./scripts/export-ui-demo.sh` after
generating the Xcode project. It needs Xcode and ffmpeg, isolates preferences,
tasks, providers and secrets, and removes only its own intermediate frames.
No real account connection, installed app replacement or public upload occurs.
