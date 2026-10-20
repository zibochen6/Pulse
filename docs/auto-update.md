# Auto-update

Pulse 0.1.3 introduces a self-built in-app updater, implemented in
`Pulse/Core/Update/`. It reads the public GitHub latest-release feed, downloads
the release ZIP, authenticates it with the published SHA-256 digest and the
Apple code signature, stages it, and installs it through a detached shell
script. No third-party framework, appcast or separate update-signing key is
involved. This document is the contract for that mechanism.

## Goals and non-goals

- Deliver a published, signed Pulse build to an installed copy without another
  manual DMG download.
- Never install code that has not passed the checksum and code-signature gate,
  and never touch task data, preferences or Keychain items.
- Never restart while the user is writing a task or reading the popover.
- Be honest about failures: a rejected download leaves the installed app
  untouched and the reason appears in Settings → Updates.

Not goals: delta updates, phased rollout, an appcast, a second update-signing
key, updating without a restart, or updating development builds and apps
outside a writable `/Applications`.

## Feed and version comparison

- The feed is
  `https://api.github.com/repos/zibochen6/Pulse/releases/latest`. It is
  public and unauthenticated; Pulse sends a `Pulse` User-Agent, accepts
  `application/vnd.github+json`, ignores caches and times out after 20
  seconds.
- Only the latest published release is considered. The parser also rejects a
  `draft` or `prerelease` payload, so a staged or upcoming build is never
  offered.
- The tag must be three numeric components, with or without a leading `v`
  (`v0.1.3` or `0.1.3`). A prerelease suffix or any other shape is rejected
  rather than guessed at, because a wrong comparison would install the wrong
  build.
- The running version comes from the bundle's `CFBundleShortVersionString`
  and `CFBundleVersion`. A missing or unreadable marketing version reads as
  `0.0.0`, so a corrupt development build never looks newer than a release.
- Versions compare numerically by major, minor and patch. Build numbers only
  break a tie when both sides carry one; a release tag has no build number, so
  it never looks newer than an installed app with the same marketing version.
- A release is offered only when its version is greater than the running one.
  The check time is saved as an ordinary preference. A version the user
  skipped is not offered again until a different version is published.
- The feed host is validated after redirects and must be HTTPS, except for the
  loopback acceptance override described under testing.

## Release assets

Each release publishes four assets, and the updater requires two of them:

- `Pulse-<version>.dmg` and `Pulse-<version>.dmg.sha256` for manual
  installation. The updater never mounts or installs the DMG.
- `Pulse-<version>.zip` and `Pulse-<version>.zip.sha256` for the updater. The
  ZIP and the DMG contain the same signed app.

The archive's `.sha256` file uses the `shasum -a 256` shape
(`<hex>  <name>`), so users can verify a download by hand. GitHub's asset
digest (`sha256:<hex>`) is used when the API provides it and must agree with
the published `.sha256` file. An archive without a published checksum is not
installable.

## Verification chain

The chain is a hard requirement, not a best-effort sequence. The digest must
be verified before the archive is unpacked, and every identity check must pass
before the download is called staged or an install script is written. Any
failure removes that update's staging directory; the installed app is never
touched.

1. **Transport and hosts.** The feed and every asset URL must be HTTPS. After
   redirects, the final URL's host must be one of `api.github.com`,
   `github.com`, `release-assets.githubusercontent.com`,
   `objects.githubusercontent.com`, `raw.githubusercontent.com`, or the
   configured feed host. Defends against protocol downgrade, redirect hijacks
   and pulling bytes from an unrelated host.
2. **Download bounds.** The advertised asset size must be at most 200 MB, the
   download must answer HTTP 200, and the received file must be non-empty.
   Defends against disk exhaustion and truncated downloads.
3. **SHA-256.** The ZIP's digest must equal the published `.sha256` value,
   and GitHub's asset digest must agree with that value. Defends against
   corrupted or tampered downloads and against release metadata that does not
   describe the bytes on disk.
4. **Archive layout.** Expansion with `ditto` must produce exactly one `.app`
   bundle and no other top-level bundle. Defends against a hidden second app,
   an unexpected layout or a masquerading payload.
5. **Signature seal.** `codesign --verify --deep --strict` must pass on the
   expanded bundle. Defends against modified nested code, a broken seal or a
   bundle that was copied without its signature.
6. **Bundle identity.** The bundle's signing identifier (read from the
   signature, which macOS derives from the bundle identifier) must be
   `dev.zibochen.Pulse`. Defends against installing a different app.
7. **Signing team and authority.** `TeamIdentifier` must be `9Y4B7WBUU2` and
   one authority must contain `Apple Development`. This is the trust anchor:
   a compromised GitHub account or release feed cannot ship code that is
   signed by the project's developer certificate.
8. **Version identity.** `CFBundleShortVersionString` must equal the release
   version (and the build number must match when the release carries one).
   Defends against a stale artifact or a signed older build presented as a
   newer release.

## Staging, restart safety and installation

- The updater's working root is `~/Library/Application Support/Pulse/Update/`.
  Each attempt downloads into `Staged/<version>/`, expands to
  `Staged/<version>/Expanded/`, and removes the archive after verification. A
  fresh launch removes the whole staging root, and a failed attempt removes
  its own directory; a leftover partial download is never installed.
- A verified download becomes a staged update. Pulse restarts to install it
  only when the popover is closed and no task draft is open. That condition is
  re-checked every 3 seconds for about 20 minutes; if it never becomes true,
  the update stays staged until Pulse quits.
- Otherwise, a banner above the task list reads "Pulse <version> is ready"
  with **Restart** and **Later** actions. Later only hides the banner for the
  current run: the update remains staged, still installs at the next safe
  moment, and is applied if Pulse quits first.
- Installation is a generated shell script at
  `~/Library/Application Support/Pulse/Update/Scripts/install-<UUID>.sh`
  (mode 0700), started detached with `nohup` so it survives Pulse exiting. It:
  1. waits up to four minutes for the old process to exit, otherwise exits
     without replacing anything;
  2. copies the current bundle to
     `~/Library/Application Support/Pulse/Backups/Pulse-<version>-<build>.app`;
  3. replaces the installed bundle with `ditto`;
  4. re-runs `codesign --verify --deep --strict` on the replacement;
  5. removes the staging root and relaunches when the user chose Restart (it
     does not relaunch after a quit).
- If the backup cannot be written, nothing is replaced. If the copy or the
  post-copy signature check fails, the script restores the backup and leaves
  the previous app in place. Every branch is appended to
  `~/Library/Logs/Pulse/update.log` with a UTC timestamp.
- Installation touches only the app bundle, the staging area, the backup and
  the log. Update preferences (automatic checks, last check, skipped version)
  are ordinary UserDefaults values and survive because the bundle is replaced,
  not migrated. `tasks.json` and Keychain items are never read, rewritten or
  migrated by the updater.

## Failure matrix

| Condition | Behavior |
| --- | --- |
| No network, DNS failure or timeout | The check reports its reason in Settings → Updates; the installed app stays as it is and the next scheduled or manual check retries. |
| GitHub rate limit (403/429) | Reported as "GitHub is rate-limiting update checks. Pulse will try again later."; no download is attempted. |
| Other feed/asset HTTP error | Reported with the status code; the staging directory is removed. |
| Malformed payload, tag or asset metadata | No download is attempted; the parse error is reported. |
| Missing ZIP or missing `.sha256` asset | No download is attempted; release is not offered as installable. |
| ZIP larger than 200 MB or empty | Download is refused before installation. |
| Checksum mismatch or malformed checksum | The download is discarded; the installed app and data are untouched. |
| GitHub digest disagrees with `.sha256` | The download is discarded; the installed app and data are untouched. |
| Archive has more or fewer than one app | The download is discarded. |
| Invalid signature, wrong identifier, wrong team or wrong authority | The download is discarded; the installed app and data are untouched. |
| Version mismatch between bundle and release | The download is discarded. |
| Pulse is not in a writable `/Applications/Pulse.app` | Updates are disabled; the status shows "Updates are disabled for development builds." |
| Old process does not exit within the installer wait | The installer logs the timeout and exits without replacing anything. |
| Backup cannot be written | The installer exits without replacing anything. |
| Bundle copy fails | The installer restores the backup. |
| Post-copy signature verification fails | The installer removes the copy, restores the backup and logs it; Pulse can be opened again. |
| Relaunch fails after a successful install | Logged; the updated app is installed and can be opened manually. |
| Pulse crashes after staging | The next launch clears the staging root instead of installing an uncontextualized update. |
| User clicks Later on the ready banner | Banner is hidden for this run; the update stays staged and still applies on quit or at the next safe moment. |

## Logs and user controls

- Settings → Updates shows the current version, the last check status, the
  automatic-check toggle, **Check Now**, **Restart to Update** when an update
  is staged, **Skip This Version** while a release is offered, and a link to
  the release notes. The toggle is on by default and is disabled when the
  app's location cannot be updated.
- Turning automatic checks off cancels the launch and six-hour checks; a
  manual **Check Now** still works and still downloads and verifies a newer
  release.
- Check, download and stage failures are shown as status text in Settings →
  Updates. They never interrupt the task list or change the installed app.
  The staged-update banner is the only update UI on Home.
- The installer is the only component that writes
  `~/Library/Logs/Pulse/update.log`. It records the wait result, backup,
  copy, signature verification, restore and relaunch branches. No
  credentials, keys or task content are ever written to it.

## Testing

Unit tests cover version parsing and comparison, latest-release and asset
parsing (draft/prerelease, missing assets, digests, malformed payloads),
checksum parsing and mismatch rejection, and install-script generation
(absolute quoting, wait, backup, copy, restore and relaunch branches).
Controller tests with injected fakes cover staging only after verification,
automatic-install gating, checksum/signature rejection, up-to-date and
skipped-version handling, apply-on-quit without relaunch, and the disabled
development-build location. These tests use synthetic payloads and temporary
directories and never reach the network, modify an installed app or read the
user's data.

The full update path is rehearsed end to end with a local feed:

1. Build a candidate app with the same bundle identifier, a higher version
   and the same Apple Development identity as the installed build. Confirm its
   `TeamIdentifier` is `9Y4B7WBUU2` and that it passes
   `codesign --verify --deep --strict`.
2. Package it the same way the release does: `ditto -c -k --keepParent
   Pulse.app Pulse-<candidate>.zip`, then
   `shasum -a 256 Pulse-<candidate>.zip > Pulse-<candidate>.zip.sha256`.
3. Write a `latest.json` shaped like the GitHub payload: `tag_name` with the
   candidate version, `draft` and `prerelease` false, and assets for the ZIP
   and `.sha256` file with `name`, `size`, `browser_download_url` values
   pointing at `http://127.0.0.1:<port>/…`, and optionally a
   `sha256:<hex>` `digest`.
4. Serve that directory with
   `python3 -m http.server <port> --bind 127.0.0.1`.
5. Launch the installed app with the override in its environment, for example
   `PULSE_UPDATE_FEED_URL=http://127.0.0.1:<port>/latest.json
   /Applications/Pulse.app/Contents/MacOS/Pulse`, then use Settings → Updates
   → **Check Now**.
6. Confirm the download, verification and staged banner; close the popover and
   let the update restart. Verify the new version, the backup, the clean log
   line, and that tasks, preferences and Keychain items are unchanged.
7. Repeat with a deliberately corrupted ZIP, a wrong checksum and an unsigned
   bundle; each must be rejected with the installed app untouched.

`PULSE_UPDATE_FEED_URL` is an acceptance-only override. It changes where the
release description is read from; it does not skip any check. Only a loopback
HTTP feed is accepted outside HTTPS, and the staged app still has to pass the
full checksum and Apple-signature chain. Production releases are always read
from the HTTPS feed.

## This is not Sparkle

Pulse does not embed Sparkle or any other updater framework. The updater is a
small, project-owned component with one feed, one archive format and one
verification path. Its trust model is: HTTPS transport, the release's
published SHA-256 digest (cross-checked with GitHub's asset digest), and the
Apple code signature bound to the project's developer certificate. There is no
appcast, no separate EdDSA update key and no third-party update binary to keep
current.

The tradeoffs are deliberate: no delta updates, no phased rollout or channels,
and no framework-maintained UI. If the project later moves to Developer ID
signing, notarization or CI signing, migrating to Sparkle becomes worthwhile:
its appcast and update-signing key then complement the distribution identity
instead of duplicating the development certificate's role. The published ZIP
assets should remain compatible so an update can deliver the switch.