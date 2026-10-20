# In-app auto-update contract

## 1. Scope / Trigger

Use when changing the updater under `Pulse/Core/Update/`, its Settings or Home
banner UI, the GitHub release feed/asset contract, or the generated install
script. Also use when a release-pipeline change affects the ZIP assets. Normal
feature work does not authorize reordering the verification chain, relaxing a
check, or moving installation earlier.

## 2. Signatures

```sh
# Public, unauthenticated feed. The parser rejects drafts and prereleases.
https://api.github.com/repos/zibochen6/Pulse/releases/latest

# Per-release assets. The updater requires the ZIP pair; the DMG pair is for people.
Pulse-<version>.dmg  Pulse-<version>.dmg.sha256
Pulse-<version>.zip  Pulse-<version>.zip.sha256

# Acceptance-only override. Changes only where the release JSON is read.
PULSE_UPDATE_FEED_URL=http://127.0.0.1:<port>/latest.json

ditto -x -k Pulse-<version>.zip <directory>
codesign --verify --deep --strict --verbose=2 <staged-app>
codesign -dv --verbose=2 <staged-app>   # Identifier, TeamIdentifier, Authority
shasum -a 256 -c Pulse-<version>.zip.sha256
```

Fixed values: bundle identifier `dev.zibochen.Pulse`; TeamIdentifier
`9Y4B7WBUU2`; signing authority containing `Apple Development`; first check
about 10 seconds after launch and then every 6 hours; 200 MB archive limit;
installer waits up to four minutes for the old process. Staging:
`~/Library/Application Support/Pulse/Update/Staged/<version>/`; scripts:
`.../Update/Scripts/install-<UUID>.sh`; backups:
`~/Library/Application Support/Pulse/Backups/Pulse-<version>-<build>.app`;
log: `~/Library/Logs/Pulse/update.log`.

## 3. Contracts

- The feed is the GitHub *latest release* endpoint and has latest-only
  semantics: one candidate, never a list. A `draft`/`prerelease` payload and a
  tag that is not `v<major>.<minor>.<patch>` (or the same without `v`) are
  rejected, not guessed. The release is offered only when its version is
  greater than the running bundle version; build numbers break ties only when
  both sides carry one. A skipped version is not re-offered until a different
  version is published.
- Required assets are `Pulse-<version>.zip` and its `.sha256` file. The
  `.sha256` file uses the `shasum -a 256` shape. GitHub's `sha256:<hex>` asset
  digest, when present, must agree with it. A release without a checksum is
  not installable. The DMG is never mounted or installed by the updater.
- Verification order is a hard requirement: HTTPS and final-redirect host
  validation, download bounds, published SHA-256 + GitHub digest, archive
  layout, `codesign --verify --deep --strict`, bundle identifier,
  TeamIdentifier + `Apple Development` authority, embedded version — all
  before a download is staged. The digest check precedes unpacking. Any
  mismatch discards the staging root and never touches the installed app.
- The only trusted signer is TeamIdentifier `9Y4B7WBUU2` with an
  `Apple Development` authority and identifier `dev.zibochen.Pulse`. This
  signature is the trust anchor; a compromised GitHub account alone must not
  be able to install code.
- Staging lives only under `~/Library/Application Support/Pulse/Update/`.
  A fresh launch clears the staging root; a failed attempt clears the staging
  root too; the archive is deleted after successful verification. A leftover
  download is never installed without a fresh verification.
- Restart safety: Pulse installs and restarts only when the popover is closed
  and no task draft is open. Otherwise it stages the update, shows the
  "Pulse <version> is ready" banner above the task list with Restart/Later,
  and keeps checking for a quiet moment. Later only hides the banner. An update
  still applies when the user quits; installation started by a quit must not
  relaunch the app.
- The updater must never modify user data: `tasks.json`, UserDefaults values
  other than the updater's own automatic-check/last-check/skipped-version
  keys, and Keychain items are untouched. Installation writes only the app
  bundle, staging, backup and update log.
- Backups go to `~/Library/Application Support/Pulse/Backups/` and are
  restored when the copy or the post-copy signature check fails. A backup
  failure means nothing was replaced. Every installer branch is logged with a
  UTC timestamp to `~/Library/Logs/Pulse/update.log`; the log must not contain
  credentials, tokens or task content.
- Updates are supported only when the running bundle is a writable
  `/Applications/Pulse.app`. Elsewhere, including development builds, the
  updater is disabled and its status says "Updates are disabled for
  development builds." It must not download or install in that state.
- Automatic checks are on by default and can be turned off in Settings →
  Updates. Manual **Check Now** remains available when automatic checks are
  off and still downloads and verifies a newer release. Failures are reported
  as status text in Settings → Updates; they never interrupt the task list.
- The install script is generated by `UpdateInstallScript` with every path
  single-quoted for `sh`, written mode 0700, and launched detached with
  `nohup` so it survives the app exiting. It waits for the old pid, backs up,
  copies with `ditto`, re-verifies the signature, restores on failure and
  optionally relaunches.
- `PULSE_UPDATE_FEED_URL` is acceptance-only. It changes only the feed
  location; every checksum and signature check still runs. Plain HTTP is
  accepted only for a loopback (`127.0.0.1`, `localhost`, `::1`) acceptance
  feed; production must be HTTPS and host-allowlisted.
- No third-party updater framework is introduced. This is not Sparkle: no
  appcast, no EdDSA key, no framework-managed install. Migration to Sparkle is
  reasonable only when the project moves to Developer ID/notarization or CI
  signing.

## 4. Validation & Error Matrix

| Condition | Required action |
| --- | --- |
| Offline, DNS failure or timeout | Report in Settings → Updates; leave the installed app and data untouched; retry on the next automatic or manual check |
| GitHub rate limit (403/429) | Report the rate-limit message; do not download; retry later |
| Malformed feed/tag/asset metadata | Reject the release; do not download |
| Missing ZIP or `.sha256` asset | Do not offer the release as installable |
| Archive over 200 MB or empty | Refuse before installation |
| Checksum mismatch or malformed checksum | Discard the staging root; installed app untouched |
| GitHub digest disagrees with `.sha256` | Discard the download |
| Archive does not contain exactly one `.app` | Discard the download |
| Invalid signature, wrong identifier/team/authority | Discard the download |
| Bundle version differs from release | Discard the download |
| Not in a writable `/Applications/Pulse.app` | Disable updates; show the development-build message |
| Old process still alive after four minutes | Installer logs the timeout and exits without replacing anything |
| Backup/copy fails | Nothing is replaced; restore the backup when the copy path failed |
| Post-copy signature check fails | Remove the copy and restore the backup |
| Relaunch fails | Log it; the update is installed and can be opened manually |
| App quits with a staged update | Apply the installer without relaunching |

## 5. Good / Base / Bad Cases

- Good: installed 0.1.3/build 7 at `/Applications/Pulse.app` reads a 0.1.4
  release, verifies ZIP/digest/signature, stages it, then restarts only after
  the popover closes; tasks, preferences and Keychain are unchanged and the
  log shows a clean install.
- Base: the Mac is offline or GitHub rate-limits the check; Settings shows the
  reason, the app keeps working, and the next check retries. A development
  build reports that updates are disabled instead of attempting an install.
- Bad: accepting a download because its checksum matched while skipping the
  signature gate; unpacking before verifying the digest; restarting while the
  task composer is open; fetching an asset from an unlisted redirect host;
  writing the installer inside the app bundle; installing a ZIP whose embedded
  version differs from the tag.

## 6. Tests Required

- Unit tests: `UpdateVersion` parsing/comparison (tag and bundle forms,
  malformed/prerelease rejection, build tie-break, unreadable bundle fallback),
  `UpdateReleaseParser` (draft/prerelease, missing assets/checksum, digest
  mapping, malformed payload/URL), `UpdateChecksum` (shasum parsing, mismatch,
  malformed), and `UpdateInstallScript` (absolute quoting, wait timeout, backup,
  copy, restore and relaunch branches).
- Controller tests with injected feed, downloader, verifier and installer
  fakes: a newer release is staged only after verification; automatic restart
  waits for an idle app; checksum and signature failures never stage; the same
  version is up to date; skipped versions are not re-offered; a staged update
  applies on quit without relaunching; a non-Applications location disables
  updates.
- Render tests: Home and Settings use an inactive update controller so the
  suite never reaches the network or installs anything.
- Local-feed rehearsal: launch the installed app with a loopback
  `PULSE_UPDATE_FEED_URL`, stage a signed higher-version ZIP, and complete the
  restart install. Repeat with a corrupted ZIP, wrong checksum and invalid
  signature; each must leave the installed app untouched. All verification
  still runs during the override.
- Release acceptance: the published ZIP matches its `.sha256` and GitHub
  digest, the updater accepts it, and the installed app, DMG and ZIP are the
  same signed bundle.

## 7. Wrong vs Correct

```swift
// Wrong: unpack or install before the digest and signature gate finishes.
let app = try DittoUnarchiver().unarchive(archiveURL, into: expandedURL)
try installer.install(plan)

// Correct: digest first, then unpack, then the full signature gate, then stage.
let publishedHex = try UpdateChecksum.parse(checksumText)
try UpdateChecksum.verify(fileAt: archiveURL, matchesPublishedHex: publishedHex)
let app = try DittoUnarchiver().unarchive(archiveURL, into: expandedURL)
try CodeSigningBundleVerifier().verify(appBundle: app, expectedVersion: release.version)
phase = .staged(StagedUpdate(release: release, appBundleURL: app, stagedAt: Date()))
```

```sh
# Wrong: point production at a plain-HTTP or unlisted host.
PULSE_UPDATE_FEED_URL=http://updates.example.com/latest.json

# Correct: production uses the HTTPS GitHub feed; loopback HTTP is acceptance only.
PULSE_UPDATE_FEED_URL=http://127.0.0.1:8765/latest.json
```