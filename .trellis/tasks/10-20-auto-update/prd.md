# In-app auto-update and one-command release

## Goal

Ship Pulse 0.1.3 with an updater the app runs itself, and a single command that
builds, verifies, installs locally and publishes a release, so a bug fix can
reach the installed app without a manual DMG round-trip.

## Requirements

1. The app checks the public GitHub `releases/latest` feed shortly after launch
   and every 6 hours; Settings → Updates offers a manual check and an
   automatic-check toggle. Draft and prerelease releases are ignored.
2. A newer release downloads `Pulse-<version>.zip`, and is accepted only after:
   HTTPS plus redirect-host allowlist, SHA-256 against the release `.sha256`
   asset and the GitHub asset digest, exactly one `Pulse.app` in the archive,
   bundle identifier `dev.zibochen.Pulse`, embedded version match,
   `codesign --verify --deep --strict`, and TeamIdentifier `9Y4B7WBUU2` with an
   Apple Development authority. Any mismatch discards the download.
3. A verified update restarts Pulse on its own only when the popover is closed
   and no task draft is open; otherwise a "Pulse x.y.z is ready" banner offers
   Restart/Later and the update is applied on quit.
4. Installation is a detached script that waits for the old process, backs up
   the bundle, replaces it, re-verifies the signature and restores on failure.
   It never touches `tasks.json`, UserDefaults or Keychain items.
5. Updates are disabled for development builds or any install outside a
   user-writable `/Applications/Pulse.app`.
6. `scripts/release.sh <version>` bumps `project.yml`, regenerates the project,
   runs the suite, builds a signed universal Release app, publishes DMG + ZIP +
   their `.sha256` files, installs that exact build locally, then commits, tags,
   pushes and creates the GitHub release.
7. Each release publishes four assets: `Pulse-<v>.dmg`, `Pulse-<v>.dmg.sha256`,
   `Pulse-<v>.zip`, `Pulse-<v>.zip.sha256`.

## Acceptance Criteria

- [x] Full suite passes (152 tests) including updater unit tests.
- [x] `scripts/release.sh 0.1.3` builds universal (arm64 + x86_64), signs with
      the Apple Development identity, and verifies DMG/ZIP payload equality.
- [x] The verified build is installed to `/Applications/Pulse.app` before the
      tag/push, and exactly one process runs from the installed path.
- [x] Tag `v0.1.3` and a non-draft, non-prerelease GitHub release carry the four
      assets with matching digests.
- [x] End-to-end rehearsal: an installed 0.1.3 discovered a locally served
      0.1.4, verified, staged, replaced itself and relaunched as 0.1.4 with one
      process, keeping a backup and cleaning its staging area; the official
      0.1.3 was then restored from the published ZIP.

## Constraints

- No third-party updater framework; the trust anchor is the existing Apple
  Development certificate plus the published digest.
- Signing remains a preview channel: not Developer ID, not notarized.
- Release artifacts and staging stay outside Git; only source, docs, tests and
  `scripts/` are committed.

## Notes

- `PULSE_UPDATE_FEED_URL` exists only to rehearse the update path against a
  local feed; every verification still runs.
- Migrate to Sparkle if Pulse ever adopts Developer ID signing, notarization or
  CI-held signing keys.
