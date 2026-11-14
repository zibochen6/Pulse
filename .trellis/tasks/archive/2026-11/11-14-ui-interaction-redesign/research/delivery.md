# Pulse 0.1.8 delivery receipt

The user explicitly authorized commit, publication and updating the local app.
Delivered 2026-11-14 through `scripts/release.sh 0.1.8 --skip-tests` after the
same product source passed 235 full-suite tests and 24 Chinese focused checks.
Two opt-in demo tests were skipped in the normal suite and run separately for
native preview/export. The release-specific safety suite passed all 18 checks.
The release command reused that test evidence and performed a fresh universal
Release build, signature, packaging, installation and publication verification.

## Published source and assets

- Release: https://github.com/zibochen6/Pulse/releases/tag/v0.1.8
- Version/build: **0.1.8 / 12**.
- Release source: `9326ce68578614840e30f274b01000b88020a72b`; `main` and the
  dereferenced `v0.1.8` tag matched at publication.
- Public latest release; neither draft nor prerelease. All four assets uploaded
  and their GitHub API digests matched the local artifact hashes.

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| Pulse-0.1.8.dmg | 2935344 | db57e116efc61faee3bc070015a64b88983aa77df22e6ce5f7a03e1128b2bc56 |
| Pulse-0.1.8.zip | 2383468 | 6a98cf1dccbd14b99a7d50ae836a6441b2fa047b21467f55bf6ed6b180f5ef11 |
| Pulse-0.1.8.dmg.sha256 | 82 | 25ee887190a92629a4904aa44bcbfc6b29d5bc47690826b482740d4827612b9e |
| Pulse-0.1.8.zip.sha256 | 82 | 913dfc72e7dbaed9071be8b744d1c737d9ed02e13072f2cb207ae79234cdcee9 |

## Installed application

- `/Applications/Pulse.app` verified as 0.1.8/build 12, one running process at
  its explicit installed executable path (PID 74147 at verification).
- Universal `x86_64 arm64`; bundle `dev.zibochen.Pulse`; Apple Development
  signature with trusted team `9Y4B7WBUU2`; strict deep signature check passed.
- The installed, staged, mounted-DMG and extracted-ZIP executables share SHA-256
  `13da6c73115e5faa35260d04cecccd27152a531707760d39b0a40e1326715344`.
- Previous 0.1.7/build 11 quit gracefully and remains backed up at
  `~/Library/Application Support/Pulse/Backups/Pulse-0.1.7-11-20261114T131150Z.nwGkS5/Pulse.app`.
- Installation replaced only the app bundle; task files, preferences and
  Keychain items were not migrated or deleted by the installer.

## Release safety and boundaries

The installer now respects declined/timed-out quit during install and rollback,
never falls back to termination signals, retains unique backups, and enforces
the updater's bundle/team/signing-channel trust tuple. Publication requires a
verified installation. Both independent review and isolated shell tests passed.

The existing `.workbuddy/` and `docs/images/` remain untracked and untouched.
No unrelated tasks are archived. Delivery log: `/tmp/Pulse-release-0.1.8.log`;
read-only preflight: `/tmp/Pulse-release-0.1.8-preflight.log`.

Native desktop control of the installed accessory app timed out; process,
bundle and signature checks do not substitute for the outstanding real popover,
drag cancellation, IME and supported-OS runtime checks listed in verification.
This remains the existing Apple Development preview channel, not notarization.
