# Pulse 0.1.9 delivery receipt

Delivered 2026-11-14 under the user's continuing commit/publish/local-update
authorization. The selected fix deletes a complete list with one Undo; it does
not try to identify tasks detached into Todo by the old implementation.

- Version/build: **0.1.9 / 13**.
- Release: https://github.com/zibochen6/Pulse/releases/tag/v0.1.9
- Tagged source: `a5aa90258ec7ea1b8e0a576c86530fe72320bc90`; remote main and
  dereferenced tag matched at publication.
- Installed `/Applications/Pulse.app` and verified a single process at that
  executable path (PID 11833 at verification).
- Universal `x86_64 arm64`, bundle `dev.zibochen.Pulse`, Apple Development team
  `9Y4B7WBUU2`; strict deep signature verification passed.
- Staged, DMG, ZIP and installed executable SHA-256:
  `aed09c86beaea5d72fa9b42e822c4a5b44285c7c579575fb3eb1e408a3ce7361`.
- Previous app backup:
  `~/Library/Application Support/Pulse/Backups/Pulse-0.1.8-12-20261114T134318Z.VP8lNO/Pulse.app`.

## Published artifacts

Public latest release, neither draft nor prerelease. All four uploaded asset
digests matched their local files after the verified installation.

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| Pulse-0.1.9.dmg | 3001098 | e45c284e0a2d37bb683ac40ee33ff87c0a5b772617e850e9133d6ac5ce02838b |
| Pulse-0.1.9.zip | 2446221 | 7304e040fbe01a272e43403d7e17da70ca860228a51d4901d3483cc4478e9dbf |
| Pulse-0.1.9.dmg.sha256 | 82 | dd855343a1f9ec058a98bb6d8f329fa63771c2adcef1407df50daa6053cec78e |
| Pulse-0.1.9.zip.sha256 | 82 | bdb053607c469c97c4f48016bff69a81bf9087ccd19fb5cec15f28265542c9db |

## Evidence and scope

`scripts/release.sh 0.1.9 --skip-tests` reused the final same-source evidence:
259 full-suite tests passed with two expected opt-in skips, plus nine Chinese
checks. It then performed a fresh universal Release build/sign/package/install
and publication verification. Log: `/tmp/Pulse-release-0.1.9.log`; preflight:
`/tmp/Pulse-release-0.1.9-preflight.log`.

Independent review, changed-file formatting, resource validation and rendered
Undo/confirmation layouts passed. Real native mouse/IME delivery is separate
from these checks. No storage migration, persistent trash or real task-file
testing was introduced. Existing `.workbuddy/` and `docs/images/` remain
untracked and untouched. This uses the existing development-signed preview
channel; it does not claim Developer ID notarization.
