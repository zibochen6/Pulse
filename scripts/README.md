# Project scripts

## Native UI demonstration

`./scripts/export-ui-demo.sh [output-directory]` renders the actual product views
with isolated sample tasks and accounts, exporting English/Chinese light/dark
screenshots and an 18-second MP4/GIF per language. It requires Xcode and ffmpeg.
Run `xcodegen generate` after adding files. Default output is
`docs/media/ui-redesign/`; no installed app, real data, credentials or network
services are used. See that directory's README for provenance and limitations.

## Release script

`scripts/release.sh` automates a Pulse macOS preview release: tests, version
bump, universal build, Apple Development signing, DMG/ZIP packaging with
`sha256` checksums, staged local install, commit, tag, non-forced push, GitHub
release, and post-publish API verification. It follows
`.trellis/spec/backend/release-delivery.md`.

```sh
./scripts/release.sh <version> [--notes <file>] [--skip-tests] \
                     [--no-install] [--no-push] [--dry-run]
```

`<version>` is the marketing version without a leading `v` (e.g. `0.1.3`).
`--notes` defaults to `docs/releases/<version>.md`. `--dry-run` performs every
read-only preflight and prints the exact commands without changing anything.
`--no-install` requires `--no-push`: publishing always follows a verified local
installation. `--skip-tests` is for an already validated source revision.

## Published assets (tag `v<version>`)

| Asset | Purpose |
| --- | --- |
| `Pulse-<version>.dmg` | drag-to-Applications disk image |
| `Pulse-<version>.dmg.sha256` | bare-filename checksum |
| `Pulse-<version>.zip` | in-app updater payload (`Pulse.app` at archive root) |
| `Pulse-<version>.zip.sha256` | bare-filename checksum |

Checksums verify from a download folder with
`shasum -a 256 -c Pulse-<version>.dmg.sha256`.

## Prerequisites

- Clean `main` checkout on `https://github.com/zibochen6/Pulse.git`; commit all
  tracked work first (only `.workbuddy/`, `docs/images/`, `.DS_Store`, this
  `scripts/` directory and the notes file may be untracked).
- `gh` authenticated as `zibochen6` with repo scope.
- Xcode command line tools, XcodeGen, `hdiutil`, `ditto`.
- One valid `Apple Development` codesigning identity; override with
  `PULSE_SIGN_IDENTITY` if needed. The script never switches identity silently.
- Release notes file (default `docs/releases/<version>.md`) must exist and be
  non-empty. `--dry-run` refuses to run without it.

## Safety

- Build and package output stays in a `mktemp -d` directory outside the repo;
  binaries are never committed.
- The app is installed only after the DMG and ZIP are verified; the previous
  `/Applications/Pulse.app` is backed up to
  a unique timestamped directory under
  `~/Library/Application Support/Pulse/Backups/`. Existing backups are retained.
  A failure after replacement attempts to restore that backup. If a running
  app declines graceful quit, restoration stops and prints the recovery path.
- A failed, cancelled or timed-out graceful quit aborts installation before
  replacement; the script never force-terminates Pulse or bypasses its draft
  protection. The same rule applies during rollback.
- Bundle identifier, Apple Development authority and team must match the
  updater's trust requirements; signer overrides cannot change that boundary.
- Pushes are never forced. Existing local/remote tags or GitHub releases make
  the script refuse and print the recovery commands instead of double-creating.
- Re-running after a partial failure stops at the first completed step with
  exact state and recovery guidance; finish the remaining step manually.
