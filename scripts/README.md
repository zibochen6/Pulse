# Release script

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
  `~/Library/Application Support/Pulse/Backups/Pulse-<oldversion>-<oldbuild>.app`.
  Any failure after replacement restores that backup.
- Pushes are never forced. Existing local/remote tags or GitHub releases make
  the script refuse and print the recovery commands instead of double-creating.
- Re-running after a partial failure stops at the first completed step with
  exact state and recovery guidance; finish the remaining step manually.