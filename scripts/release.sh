#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scripts/release.sh - Pulse macOS preview release automation.
#
#   scripts/release.sh <version> [--notes <file>] [--skip-tests]
#                      [--no-install] [--no-push] [--dry-run]
#
#   <version>      Marketing version without a leading "v" (e.g. 0.1.3); the
#                  tag is v<version> and the build number is the current
#                  CURRENT_PROJECT_VERSION + 1 (written to project.yml).
#   --notes <f>    Release notes file (default: docs/releases/<version>.md).
#   --skip-tests   Skip the Debug unit-test run.
#   --no-install   Do not replace /Applications/Pulse.app.
#   --no-push      Stop before commit/tag/push/GitHub release.
#   --dry-run      Read-only preflight; print every command; change nothing.
#
# Published assets for v<version>:
#   Pulse-<version>.zip          in-app updater payload (ditto -c -k --keepParent)
#   Pulse-<version>.zip.sha256   bare-filename checksum; `shasum -a 256 -c` works
#   Pulse-<version>.dmg          drag-to-Applications UDZO image
#   Pulse-<version>.dmg.sha256   bare-filename checksum; `shasum -a 256 -c` works
#
# One Apple Development-signed universal (arm64 + x86_64) app is the ZIP
# payload, the DMG payload and the local install. Build/sign/package output
# stays in a mktemp -d directory outside the repository; binaries are never
# committed. Requires clean `main`, gh authenticated as zibochen6, XcodeGen and
# one valid "Apple Development" identity (override: PULSE_SIGN_IDENTITY).
# Untracked files are tolerated only in .workbuddy/, docs/images/, .DS_Store,
# scripts/ (this tool) and the notes file.
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_SLUG="zibochen6/Pulse"
INSTALLED_APP="/Applications/Pulse.app"
BACKUP_ROOT="$HOME/Library/Application Support/Pulse/Backups"

VERSION=""; NOTES_ARG=""; SKIP_TESTS=0; NO_INSTALL=0; NO_PUSH=0; DRY_RUN=0
STAGE=""; MOUNT_DIR=""; DMG_DEV=""; INSTALL_ACTIVE=0; BACKUP_APP=""; PUBLISHED=0

die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
step() { printf '\n==> %s\n' "$*"; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1"; }

usage() {
  cat <<'EOF'
Usage: scripts/release.sh <version> [options]

  <version>        Marketing version without a leading "v" (e.g. 0.1.3).
  --notes <file>   Release notes file (default: docs/releases/<version>.md).
  --skip-tests     Skip the Debug unit-test run.
  --no-install     Do not replace /Applications/Pulse.app.
  --no-push        Stop before commit/tag/push/GitHub release.
  --dry-run        Read-only preflight; print every command; change nothing.
  -h, --help       Show this help.

Publishes for v<version>: Pulse-<version>.zip, Pulse-<version>.zip.sha256,
Pulse-<version>.dmg, Pulse-<version>.dmg.sha256.
EOF
}

sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
app_version() { plutil -extract CFBundleShortVersionString raw "$1/Contents/Info.plist" 2>/dev/null; }
app_build() { plutil -extract CFBundleVersion raw "$1/Contents/Info.plist" 2>/dev/null; }

assert_meta() { # <app> <version> <build> <label>
  local v b
  v="$(app_version "$1")" || die "$4: cannot read CFBundleShortVersionString from $1"
  b="$(app_build "$1")" || die "$4: cannot read CFBundleVersion from $1"
  [ "$v" = "$2" ] && [ "$b" = "$3" ] || die "$4: version/build is '$v'/'$b', expected '$2'/'$3' ($1)"
}

verify_signed() { # <app> <label>
  local authority
  [ -d "$1" ] || die "$2: app bundle not found at $1"
  codesign --verify --deep --strict "$1" >/dev/null 2>&1 || die "$2: codesign --verify --deep --strict failed for $1"
  authority="$(codesign -dv "$1" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
  [ "$authority" = "$IDENTITY" ] || die "$2: signature authority '${authority:-none}' != '$IDENTITY'"
}

assert_hash() { # <app> <expected_sha256> <label>
  local h
  h="$(sha256_file "$1/Contents/MacOS/Pulse")"
  [ "$h" = "$2" ] || die "$3: executable sha256 $h does not match the staged app's $2"
}

yml_count() { grep -cE "^[[:space:]]*$1:" project.yml || true; }
yml_get() { sed -n -E "s/^[[:space:]]*$1:[[:space:]]*//p" project.yml | head -1 | tr -d '[:space:]'; }

yml_set() { # <KEY> <value>; anchored on the single key inside targets.Pulse.settings.base
  [ "$(yml_count "$1")" = "1" ] || die "project.yml: expected exactly one '$1:' line (targets.Pulse.settings.base), found $(yml_count "$1")"
  sed -i '' -E "s|^([[:space:]]*)$1:.*\$|\1$1: $2|" project.yml
  [ "$(yml_get "$1")" = "$2" ] || die "project.yml: failed to set $1 to $2"
}

version_gt() { # true when $1 > $2 as MAJOR.MINOR.PATCH
  local a b c x y z
  IFS=. read -r a b c <<< "$1"; IFS=. read -r x y z <<< "$2"
  [ "$((10#${a:-0}))" -gt "$((10#${x:-0}))" ] && return 0
  [ "$((10#${a:-0}))" -lt "$((10#${x:-0}))" ] && return 1
  [ "$((10#${b:-0}))" -gt "$((10#${y:-0}))" ] && return 0
  [ "$((10#${b:-0}))" -lt "$((10#${y:-0}))" ] && return 1
  [ "$((10#${c:-0}))" -gt "$((10#${z:-0}))" ] && return 0
  return 1
}

build_setting() { # <Debug|Release> <KEY>
  xcodebuild -project Pulse.xcodeproj -target Pulse -configuration "$1" -showBuildSettings 2>/dev/null \
    | awk -v k="$2" '$1 == k && $2 == "=" { print $3; exit }'
}

resolve_identity() {
  local available
  available="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if [ -n "${PULSE_SIGN_IDENTITY:-}" ]; then
    printf '%s\n' "$available" | grep -Fq "\"$PULSE_SIGN_IDENTITY\"" \
      || die "PULSE_SIGN_IDENTITY='$PULSE_SIGN_IDENTITY' is not a valid codesigning identity. Available:\n$available"
    IDENTITY="$PULSE_SIGN_IDENTITY"
  else
    IDENTITY="$(printf '%s\n' "$available" | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
    [ -n "$IDENTITY" ] || IDENTITY="$(printf '%s\n' "$available" | sed -n 's/.*"\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$IDENTITY" ] || die "No codesigning identity found. Install an Apple Development certificate or set PULSE_SIGN_IDENTITY."
  fi
}

quit_pulse() {
  local pids deadline pid
  pids="$(pgrep -x Pulse || true)"
  [ -n "$pids" ] || return 0
  printf '  Pulse running (pid(s): %s); requesting a graceful quit\n' "$(printf '%s' "$pids" | tr '\n' ' ')"
  osascript -e 'quit app "Pulse"' >/dev/null 2>&1 || {
    warn "AppleScript quit failed; sending SIGTERM"
    for pid in $pids; do kill -TERM "$pid" 2>/dev/null || true; done
  }
  deadline=$((SECONDS + 15))
  while pgrep -x Pulse >/dev/null 2>&1 && [ "$SECONDS" -lt $((deadline - 5)) ]; do sleep 0.5; done
  if pgrep -x Pulse >/dev/null 2>&1; then
    warn "Pulse did not exit after the graceful request; sending SIGTERM"
    for pid in $(pgrep -x Pulse || true); do kill -TERM "$pid" 2>/dev/null || true; done
    while pgrep -x Pulse >/dev/null 2>&1 && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.5; done
  fi
  if pgrep -x Pulse >/dev/null 2>&1; then
    die "Pulse did not quit within 15s (pid(s): $(pgrep -x Pulse | tr '\n' ' ')). Refusing to force-kill; quit Pulse manually (Settings > Quit Pulse) and rerun."
  fi
  printf '  Pulse quit cleanly\n'
}

restore_previous_app() {
  local pids pid deadline
  if [ -z "${BACKUP_APP:-}" ] || [ ! -d "$BACKUP_APP" ]; then
    warn "no previous app backup to restore; $INSTALLED_APP left in its current state"
    return 0
  fi
  pids="$(pgrep -x Pulse || true)"
  if [ -n "$pids" ]; then
    osascript -e 'quit app "Pulse"' >/dev/null 2>&1 || true
    for pid in $pids; do kill -TERM "$pid" 2>/dev/null || true; done
    deadline=$((SECONDS + 10))
    while pgrep -x Pulse >/dev/null 2>&1 && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.5; done
  fi
  rm -rf "$INSTALLED_APP"
  if ditto "$BACKUP_APP" "$INSTALLED_APP"; then
    open "$INSTALLED_APP" >/dev/null 2>&1 || true
    warn "restored the previous Pulse app from $BACKUP_APP and relaunched it"
  else
    warn "RESTORE FAILED. Manual recovery: ditto \"$BACKUP_APP\" \"$INSTALLED_APP\""
  fi
}

cleanup() {
  local rc=$?
  trap - EXIT; set +e
  if [ -n "${DMG_DEV:-}" ]; then
    hdiutil detach "$DMG_DEV" -quiet >/dev/null 2>&1 || hdiutil detach "$DMG_DEV" -force >/dev/null 2>&1
  fi
  if [ "${INSTALL_ACTIVE:-0}" = 1 ]; then
    printf '\nINTERRUPTED after replacing %s - restoring the previous app...\n' "$INSTALLED_APP" >&2
    restore_previous_app
  fi
  exit "$rc"
}

plan_text() {
  cat <<'PLAN'
  STAGE="$(mktemp -d "${TMPDIR:-/tmp}/pulse-release-@VERSION@.XXXXXX")"
  mkdir -p "$STAGE/artifacts" "$STAGE/dmg-root" "$STAGE/mnt" "$STAGE/zip-check"

  # 2. Tests (Debug, signing disabled)
  xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$STAGE/DerivedData" CODE_SIGNING_ALLOWED=NO test

  # 3. Version bump: project.yml only (0.1.2/build @CURBUILD@ -> @VERSION@/@BUILD@), then regenerate
  sed -i '' -E 's|^([[:space:]]*)MARKETING_VERSION:.*$|\1MARKETING_VERSION: @VERSION@|' project.yml
  sed -i '' -E 's|^([[:space:]]*)CURRENT_PROJECT_VERSION:.*$|\1CURRENT_PROJECT_VERSION: @BUILD@|' project.yml
  xcodegen generate
  xcodebuild -project Pulse.xcodeproj -target Pulse -configuration Debug -showBuildSettings    # expect @VERSION@ / @BUILD@
  xcodebuild -project Pulse.xcodeproj -target Pulse -configuration Release -showBuildSettings  # expect @VERSION@ / @BUILD@

  # 4. Universal Release build (unsigned), then sign exactly that bundle
  xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$STAGE/DerivedData" \
    CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' build
  APP="$STAGE/DerivedData/Build/Products/Release/Pulse.app"
  lipo -archs "$APP/Contents/MacOS/Pulse"                    # must contain arm64 and x86_64
  codesign --force --sign "@IDENTITY@" --timestamp=none "$APP"
  codesign --verify --deep --strict "$APP"
  plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist"   # @VERSION@
  plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist"              # @BUILD@

  # 5. Package into $STAGE/artifacts (outside the repository)
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/artifacts/Pulse-@VERSION@.zip"
  ditto "$APP" "$STAGE/dmg-root/Pulse.app" && ln -s /Applications "$STAGE/dmg-root/Applications"
  hdiutil create -volname Pulse -srcfolder "$STAGE/dmg-root" -ov -format UDZO "$STAGE/artifacts/Pulse-@VERSION@.dmg"
  ( cd "$STAGE/artifacts" && shasum -a 256 Pulse-@VERSION@.zip > Pulse-@VERSION@.zip.sha256 )
  ( cd "$STAGE/artifacts" && shasum -a 256 Pulse-@VERSION@.dmg > Pulse-@VERSION@.dmg.sha256 )
  ( cd "$STAGE/artifacts" && shasum -a 256 -c Pulse-@VERSION@.zip.sha256 && shasum -a 256 -c Pulse-@VERSION@.dmg.sha256 )

  # 6. Mount the DMG read-only, verify signature/version/build/bytes + Applications link, always detach
  hdiutil attach -nobrowse -readonly -mountpoint "$STAGE/mnt" "$STAGE/artifacts/Pulse-@VERSION@.dmg"
  codesign --verify --deep --strict "$STAGE/mnt/Pulse.app"
  shasum -a 256 "$STAGE/mnt/Pulse.app/Contents/MacOS/Pulse"   # equals the staged app's sha256
  hdiutil detach <device>

  # 7. Unzip the updater payload and verify the same executable bytes
  ditto -x -k "$STAGE/artifacts/Pulse-@VERSION@.zip" "$STAGE/zip-check"

  # 8. Local install (skipped with --no-install): graceful quit, backup, replace, verify one process
  osascript -e 'quit app "Pulse"'          # waits up to 15s; never force-kills
  ditto /Applications/Pulse.app "$HOME/Library/Application Support/Pulse/Backups/Pulse-@OLDVER@-@OLDBUILD@.app"
  rm -rf /Applications/Pulse.app && ditto "$APP" /Applications/Pulse.app
  open /Applications/Pulse.app             # verify exactly one pid at the installed path

  # 9. Publish source + assets (skipped with --no-push); never force-push
  git add -A -- project.yml Pulse.xcodeproj Pulse Tests scripts docs .trellis README.md ':(exclude)docs/images'
  git commit -m "release: prepare Pulse @VERSION@"
  git tag -a v@VERSION@ -m "Pulse @VERSION@"
  git push origin main
  git push origin v@VERSION@
  gh release create v@VERSION@ --repo zibochen6/Pulse --title "Pulse @VERSION@" \
    --notes-file "@NOTES@" --verify-tag \
    "$STAGE/artifacts/Pulse-@VERSION@.dmg" "$STAGE/artifacts/Pulse-@VERSION@.zip" \
    "$STAGE/artifacts/Pulse-@VERSION@.dmg.sha256" "$STAGE/artifacts/Pulse-@VERSION@.zip.sha256"

  # 10. Verify via the API: latest tag, not draft/prerelease, four assets with sizes + sha256 digests
  gh api repos/zibochen6/Pulse/releases/latest --jq '.tag_name, .assets[].name'
PLAN
}

print_plan() {
  printf '\nDry run: all read-only preflight checks passed, nothing has been changed.\n'
  printf 'Flags: skip-tests=%s no-install=%s no-push=%s\n' "$SKIP_TESTS" "$NO_INSTALL" "$NO_PUSH"
  printf 'The plan below is the full run; a set flag skips its step (2, 8 or 9-10).\n'
  printf 'Commands that would run (in order):\n\n'
  plan_text | sed -e "s|@VERSION@|$VERSION|g" -e "s|@BUILD@|$NEW_BUILD|g" \
    -e "s|@CURBUILD@|$CURRENT_BUILD|g" -e "s|@IDENTITY@|$IDENTITY|g" \
    -e "s|@NOTES@|$NOTES_FILE|g" -e "s|@OLDVER@|${OLD_INSTALLED_VERSION:-unknown}|g" \
    -e "s|@OLDBUILD@|${OLD_INSTALLED_BUILD:-unknown}|g"
}

install_app() {
  local installed_version installed_build pids count pid comm deadline
  [ -w /Applications ] || die "/Applications is not writable by $(id -un); cannot install. Re-run with --no-install to skip the local install."
  installed_version="$(app_version "$INSTALLED_APP" || true)"
  installed_build="$(app_build "$INSTALLED_APP" || true)"
  quit_pulse
  if [ -d "$INSTALLED_APP" ]; then
    BACKUP_APP="$BACKUP_ROOT/Pulse-${installed_version:-unknown}-${installed_build:-unknown}.app"
    mkdir -p "$BACKUP_ROOT" || die "cannot create backup directory $BACKUP_ROOT"
    [ ! -d "$BACKUP_APP" ] || rm -rf "$BACKUP_APP"
    printf '  backing up the installed app to %s\n' "$BACKUP_APP"
    ditto "$INSTALLED_APP" "$BACKUP_APP" || {
      open "$INSTALLED_APP" >/dev/null 2>&1 || true
      die "failed to back up $INSTALLED_APP to $BACKUP_APP. The installed app was left untouched and relaunched; nothing was replaced."
    }
    assert_meta "$BACKUP_APP" "$installed_version" "$installed_build" "backup"
  else
    printf '  no existing %s; performing a fresh install\n' "$INSTALLED_APP"
  fi
  INSTALL_ACTIVE=1
  rm -rf "$INSTALLED_APP"
  ditto "$APP" "$INSTALLED_APP" || die "failed to copy $APP to $INSTALLED_APP"
  verify_signed "$INSTALLED_APP" "installed app"
  assert_meta "$INSTALLED_APP" "$VERSION" "$NEW_BUILD" "installed app"
  assert_hash "$INSTALLED_APP" "$APP_EXEC_HASH" "installed app"
  open "$INSTALLED_APP" || die "open $INSTALLED_APP failed"
  deadline=$((SECONDS + 15))
  while ! pgrep -x Pulse >/dev/null 2>&1; do
    [ "$SECONDS" -lt "$deadline" ] || die "Pulse did not start within 15s after opening $INSTALLED_APP"
    sleep 0.5
  done
  sleep 1
  pids="$(pgrep -x Pulse || true)"
  count="$(printf '%s\n' "$pids" | grep -c . || true)"
  [ "$count" = "1" ] || die "expected exactly one running Pulse process, found $count (pid(s): $(printf '%s' "$pids" | tr '\n' ' '))"
  pid="$pids"
  comm="$(ps -p "$pid" -o comm= | sed 's/[[:space:]]*$//')"
  [ "$comm" = "$INSTALLED_APP/Contents/MacOS/Pulse" ] || die "Pulse process $pid runs '$comm', expected '$INSTALLED_APP/Contents/MacOS/Pulse'"
  printf '  installed app verified: one process (pid %s) at %s\n' "$pid" "$comm"
  INSTALL_ACTIVE=0
}

publish_recovery_hint() {
  printf '\nThe signed artifacts are at: %s\n' "${ARTIFACTS:-<stage>/artifacts}"
  printf 'Check remote state first: git ls-remote --heads origin main; git ls-remote --tags origin %s\n' "$TAG"
  printf 'Recovery commands (only after inspecting the state above):\n'
  printf '  git push origin main\n  git push origin %s\n' "$TAG"
  printf '  gh release create %s --repo %s --title "Pulse %s" --notes-file "%s" --verify-tag \\\n' "$TAG" "$REPO_SLUG" "$VERSION" "$NOTES_FILE"
  printf '    "%s" "%s" "%s" "%s"\n' "${DMG_FILE:-}" "${ZIP_FILE:-}" "${DMG_SHA:-}" "${ZIP_SHA:-}"
}

die_publish() { printf '\nERROR: %s\n' "$1" >&2; publish_recovery_hint >&2; exit 1; }

publish_release() {
  local staged_names release_commit tag_sha remote_main remote_tag
  git add -A -- project.yml Pulse.xcodeproj Pulse Tests scripts docs .trellis README.md ':(exclude)docs/images' \
    || die "git add failed; nothing was committed."
  staged_names="$(git diff --cached --name-only)"
  [ -n "$staged_names" ] || die "Nothing staged for the release commit."
  printf '%s\n' "$staged_names" | grep -qx 'project.yml' \
    || die "The project.yml version bump is not staged; aborting before commit.\nStaged:\n$staged_names"
  if printf '%s\n' "$staged_names" | grep -Eq '^(\.workbuddy/|docs/images/)'; then
    die "Refusing to commit .workbuddy/ or docs/images/ content.\nStaged:\n$staged_names"
  fi
  printf '  staged files:\n%s\n' "$(printf '%s\n' "$staged_names" | sed 's/^/    /')"
  git commit -m "release: prepare Pulse $VERSION" \
    || die "git commit failed (check git user.name/user.email and commit signing). Release changes are still staged; nothing was pushed."
  release_commit="$(git rev-parse HEAD)"
  tag_sha="$(git rev-parse -q --verify "refs/tags/$TAG" 2>/dev/null || true)"
  if [ -n "$tag_sha" ]; then
    [ "$tag_sha" = "$release_commit" ] || die_publish "Tag $TAG exists locally at $tag_sha, not at the new release commit $release_commit."
  else
    git tag -a "$TAG" -m "Pulse $VERSION" || die_publish "git tag -a $TAG failed; release commit $release_commit exists but is not tagged. Nothing was pushed."
  fi
  [ -z "$(git status --porcelain --untracked-files=no)" ] \
    || die_publish "Tracked files changed while preparing the release commit; refusing to push an inconsistent tree. Inspect: git status"
  printf '  pushing main...\n'
  if ! git push origin main; then
    die_publish "git push origin main failed (non-forced fast-forward required). Local commit $release_commit and tag $TAG exist; origin/main was NOT updated. Do not force-push. If HTTPS fails while gh works, check the system proxy and retry with a per-command proxy, e.g. git -c http.proxy=<proxy> push origin main."
  fi
  if ! git push origin "$TAG"; then
    die_publish "git push origin $TAG failed; main was updated but the tag is not on origin. Retry: git push origin $TAG"
  fi
  remote_main="$(git ls-remote --heads origin main | awk '{print $1}')"
  [ "$remote_main" = "$release_commit" ] || die_publish "origin/main is '$remote_main', expected $release_commit. Inspect: git ls-remote --heads origin main"
  remote_tag="$(git ls-remote --tags origin | awk -v t="refs/tags/$TAG" '$2 == t || $2 == t "^{}" { print $1 }' | tail -1)"
  [ "$remote_tag" = "$release_commit" ] || die_publish "origin tag $TAG resolves to '$remote_tag', expected $release_commit. Inspect: git ls-remote --tags origin"
  printf '  main and %s pushed (%s)\n' "$TAG" "$release_commit"
  if gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
    die_publish "GitHub release $TAG already exists. Refusing to double-create; inspect: gh release view $TAG --repo $REPO_SLUG."
  fi
  printf '  creating GitHub release %s...\n' "$TAG"
  if ! gh release create "$TAG" --repo "$REPO_SLUG" --title "Pulse $VERSION" --notes-file "$NOTES_FILE" --verify-tag \
      "$DMG_FILE" "$ZIP_FILE" "$DMG_SHA" "$ZIP_SHA"; then
    die_publish "gh release create $TAG failed; main and the tag are pushed. Upload outcome is unknown - verify before retrying: gh release view $TAG --repo $REPO_SLUG. If the release exists without all four assets: gh release upload $TAG <files> --clobber"
  fi
  PUBLISHED=1
}

verify_published_release() {
  local latest_meta latest_tag draft prerelease name file local_hash asset count size digest
  latest_meta="$(gh api "repos/$REPO_SLUG/releases/latest" --jq '"\(.tag_name) \(.draft) \(.prerelease)"')" \
    || die "cannot read repos/$REPO_SLUG/releases/latest via the GitHub API (network/permissions?)"
  read -r latest_tag draft prerelease <<< "$latest_meta"
  [ "$latest_tag" = "$TAG" ] || die "releases/latest is '$latest_tag', expected '$TAG'. A newer release may exist; inspect before announcing."
  [ "$draft" = "false" ] || die "release $TAG is still a draft"
  [ "$prerelease" = "false" ] || die "release $TAG is marked as a prerelease"
  for name in "Pulse-$VERSION.dmg" "Pulse-$VERSION.zip" "Pulse-$VERSION.dmg.sha256" "Pulse-$VERSION.zip.sha256"; do
    file="$ARTIFACTS/$name"
    [ -f "$file" ] || die "local artifact missing: $file"
    local_hash="$(sha256_file "$file")"
    asset="$(gh api "repos/$REPO_SLUG/releases/latest" --jq ".assets[] | select(.name == \"$name\") | \"\(.size) \(.digest)\"")" || die "GitHub API asset query failed for $name"
    count="$(printf '%s\n' "$asset" | grep -c . || true)"
    [ "$count" = "1" ] || die "expected exactly one release asset named $name, found $count"
    size="${asset%% *}"; digest="${asset#* }"
    case "$size" in ''|*[!0-9]*) die "asset $name has a non-numeric size: '$asset'";; esac
    [ "$size" -gt 0 ] || die "asset $name is empty"
    [ "$digest" = "sha256:$local_hash" ] || die "asset $name digest '$digest' does not match local sha256 'sha256:$local_hash'"
    printf '  %-30s %9s bytes  sha256:%s\n' "$name" "$size" "$local_hash"
  done
}

trap cleanup EXIT

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --notes) [ "$#" -ge 2 ] || die "--notes requires a file argument"; NOTES_ARG="$2"; shift 2 ;;
    --notes=*) NOTES_ARG="${1#*=}"; shift ;;
    --skip-tests) SKIP_TESTS=1; shift ;;
    --no-install) NO_INSTALL=1; shift ;;
    --no-push) NO_PUSH=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --*) die "unknown option: $1 (try --help)" ;;
    *) [ -z "$VERSION" ] || die "unexpected argument: $1"; VERSION="$1"; shift ;;
  esac
done

[ -n "$VERSION" ] || { usage >&2; exit 2; }
case "$VERSION" in v*) die "pass the version without a leading 'v' (got '$VERSION', use '${VERSION#v}')";; esac
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid version '$VERSION': expected MAJOR.MINOR.PATCH without a leading 'v', e.g. 0.1.3"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository; run this script from the Pulse checkout"
cd "$REPO_ROOT"
TAG="v$VERSION"
[ "$(uname -s)" = "Darwin" ] || die "this release script supports macOS only"

if [ -n "$NOTES_ARG" ]; then
  case "$NOTES_ARG" in /*) NOTES_FILE="$NOTES_ARG" ;; *) NOTES_FILE="$REPO_ROOT/$NOTES_ARG" ;; esac
else
  NOTES_FILE="$REPO_ROOT/docs/releases/$VERSION.md"
fi
NOTES_DIR="$(cd "$(dirname "$NOTES_FILE")" 2>/dev/null && pwd)" || NOTES_DIR=""
[ -z "$NOTES_DIR" ] || NOTES_FILE="$NOTES_DIR/$(basename "$NOTES_FILE")"
NOTES_REL=""
case "$NOTES_FILE" in "$REPO_ROOT"/*) NOTES_REL="${NOTES_FILE#"$REPO_ROOT"/}" ;; esac

step "1/10 Preflight"
for tool in git gh xcodegen xcodebuild ditto hdiutil shasum codesign lipo plutil security osascript open pgrep ps awk sed mktemp; do need_cmd "$tool"; done
if grep -qE '^[[:space:]]*- path: Tests/Fixtures' project.yml && [ ! -d Tests/Fixtures ]; then
  die "project.yml lists 'Tests/Fixtures' as a source, but that directory does not exist (git does not track empty dirs). Run: mkdir -p Tests/Fixtures, or remove that source from project.yml. Refusing to fail later inside xcodegen."
fi

BRANCH="$(git branch --show-current)"
[ "$BRANCH" = "main" ] || die "must run on branch main (currently: '${BRANCH:-detached HEAD}'). Check out main and rerun."
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
case "$ORIGIN_URL" in
  *github.com[:/]*"$REPO_SLUG"*) ;;
  *) die "git remote origin is '${ORIGIN_URL:-<missing>}', expected https://github.com/$REPO_SLUG.git" ;;
esac

TRACKED_DIRTY="$(git status --porcelain --untracked-files=no)"
if [ -n "$TRACKED_DIRTY" ]; then
  printf '%s\n' "$TRACKED_DIRTY" >&2
  die "Working tree has staged/unstaged changes to tracked files. Commit or stash them before releasing; nothing was modified."
fi
UNTRACKED="$(git ls-files --others --exclude-standard -z | tr '\0' '\n')"
BAD_UNTRACKED=""
if [ -n "$UNTRACKED" ]; then
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in .workbuddy/*|docs/images/*|.DS_Store|*/.DS_Store|scripts/*|"$NOTES_REL") continue ;; esac
    BAD_UNTRACKED="${BAD_UNTRACKED}  ${path}"$'\n'
  done <<< "$UNTRACKED"
  [ -z "$BAD_UNTRACKED" ] || die "Unexpected untracked files (commit or remove them first; only .workbuddy/, docs/images/, .DS_Store, scripts/ and the notes file are tolerated):"$'\n'"$BAD_UNTRACKED"
fi
printf '  working tree clean (branch main, HEAD %s)\n' "$(git rev-parse --short HEAD)"

REMOTE_TAG_REFS="$(git ls-remote --tags origin "refs/tags/$TAG" 2>&1)" || die "cannot query origin tags (network/proxy failure?):"$'\n'"$REMOTE_TAG_REFS"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  die "Local tag $TAG already exists at $(git rev-parse --short "$TAG"). Refusing to double-create. If this is a partial earlier release, inspect:
  git show --stat $TAG
  git ls-remote --tags origin $TAG
  gh release view $TAG --repo $REPO_SLUG
If the tag is wrong, delete it explicitly with: git tag -d $TAG. If the release is incomplete, finish the remaining step manually."
fi
[ -z "$REMOTE_TAG_REFS" ] || die "Remote tag $TAG already exists on origin:"$'\n'"$REMOTE_TAG_REFS"$'\n'"Refusing to overwrite an existing release tag."

if ! GH_STATUS="$(gh auth status 2>&1)"; then
  printf '%s\n' "$GH_STATUS" | sed -E 's/(Token:).*/\1 [redacted]/' >&2
  die "gh is not authenticated. Run: gh auth login (account zibochen6 with repo scope)"
fi
printf '%s\n' "$GH_STATUS" | grep -q 'account zibochen6' || die "gh active account is not zibochen6; run: gh auth switch --user zibochen6"

[ -f "$NOTES_FILE" ] || die "release notes file not found: $NOTES_FILE"$'\n'"Create it (see docs/releases/0.1.2.md for the format) or pass --notes <file>."
[ -s "$NOTES_FILE" ] || die "release notes file is empty: $NOTES_FILE"

resolve_identity
printf '  signing identity: %s\n' "$IDENTITY"
if [ -d "$INSTALLED_APP" ]; then
  INSTALLED_AUTHORITY="$(codesign -dv "$INSTALLED_APP" 2>&1 | sed -n 's/^Authority=//p' | head -1 || true)"
  if [ -n "$INSTALLED_AUTHORITY" ] && [ "$INSTALLED_AUTHORITY" != "$IDENTITY" ] && [ -z "${PULSE_SIGN_IDENTITY:-}" ]; then
    die "The installed app is signed by '$INSTALLED_AUTHORITY' but the resolved identity is '$IDENTITY'. Refusing to silently switch signing identity; set PULSE_SIGN_IDENTITY explicitly if intended."
  fi
fi

[ "$(yml_count MARKETING_VERSION)" = "1" ] || die "project.yml: expected exactly one MARKETING_VERSION line under targets.Pulse.settings.base, found $(yml_count MARKETING_VERSION)"
[ "$(yml_count CURRENT_PROJECT_VERSION)" = "1" ] || die "project.yml: expected exactly one CURRENT_PROJECT_VERSION line under targets.Pulse.settings.base, found $(yml_count CURRENT_PROJECT_VERSION)"
CURRENT_VERSION="$(yml_get MARKETING_VERSION)"
CURRENT_BUILD="$(yml_get CURRENT_PROJECT_VERSION)"
[[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]] || die "project.yml CURRENT_PROJECT_VERSION '$CURRENT_BUILD' is not an integer"
NEW_BUILD=$((CURRENT_BUILD + 1))
if [ "$CURRENT_VERSION" = "$VERSION" ]; then
  die "project.yml already says MARKETING_VERSION $VERSION: a previous run stopped after the version bump. Refusing to bump again. Inspect:
  git log -1 --format=%s
  git tag -l $TAG
  gh release view $TAG --repo $REPO_SLUG
Finish the interrupted release manually, or revert the bump (git checkout -- project.yml Pulse.xcodeproj) before retrying."
fi
version_gt "$VERSION" "$CURRENT_VERSION" || die "version $VERSION must be greater than the current project.yml version $CURRENT_VERSION"
printf '  version: %s -> %s, build: %s -> %s\n' "$CURRENT_VERSION" "$VERSION" "$CURRENT_BUILD" "$NEW_BUILD"
printf '  notes: %s\n' "$NOTES_FILE"
if [ -d "$INSTALLED_APP" ]; then
  OLD_INSTALLED_VERSION="$(app_version "$INSTALLED_APP" || true)"
  OLD_INSTALLED_BUILD="$(app_build "$INSTALLED_APP" || true)"
  printf '  installed app: %s (version %s, build %s)\n' "$INSTALLED_APP" "${OLD_INSTALLED_VERSION:-unknown}" "${OLD_INSTALLED_BUILD:-unknown}"
else
  OLD_INSTALLED_VERSION=""; OLD_INSTALLED_BUILD=""
  printf '  installed app: none (fresh install)\n'
fi

if [ "$DRY_RUN" = 1 ]; then
  print_plan
  printf '\nDRY RUN OK: preflight passed; no files, tags, releases or apps were changed.\n'
  exit 0
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/pulse-release-$VERSION.XXXXXX")"
ARTIFACTS="$STAGE/artifacts"
mkdir -p "$ARTIFACTS" "$STAGE/dmg-root" "$STAGE/mnt" "$STAGE/zip-check"
printf '  staging outside the repository: %s\n' "$STAGE"

step "2/10 Tests (Debug, code signing disabled)"
if [ "$SKIP_TESTS" = 1 ]; then
  printf '  skipped (--skip-tests)\n'
else
  if ! xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' \
      -derivedDataPath "$STAGE/DerivedData" CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$STAGE/tests.log"; then
    die "Unit tests failed (xcodebuild exited non-zero). Log: $STAGE/tests.log. No version bump or build was performed."
  fi
  if grep -q '\*\* TEST FAILED \*\*' "$STAGE/tests.log"; then die "Unit tests reported '** TEST FAILED **'. Log: $STAGE/tests.log"; fi
  printf '  tests passed\n'
fi

step "3/10 Bump version in project.yml and regenerate the Xcode project"
yml_set MARKETING_VERSION "$VERSION"
yml_set CURRENT_PROJECT_VERSION "$NEW_BUILD"
[ "$(git diff --numstat -- project.yml | awk '{print $1 ":" $2}')" = "2:2" ] \
  || die "version bump changed more than the two expected lines in project.yml:"$'\n'"$(git diff -- project.yml)"
xcodegen generate || die "xcodegen generate failed; project.yml was updated but the Xcode project was not regenerated"
grep -q "MARKETING_VERSION = $VERSION;" Pulse.xcodeproj/project.pbxproj || die "generated project does not embed MARKETING_VERSION = $VERSION; run: xcodegen generate"
grep -q "CURRENT_PROJECT_VERSION = $NEW_BUILD;" Pulse.xcodeproj/project.pbxproj || die "generated project does not embed CURRENT_PROJECT_VERSION = $NEW_BUILD; run: xcodegen generate"
for CONFIG in Debug Release; do
  SETTING_VERSION="$(build_setting "$CONFIG" MARKETING_VERSION)"
  SETTING_BUILD="$(build_setting "$CONFIG" CURRENT_PROJECT_VERSION)"
  [ "$SETTING_VERSION" = "$VERSION" ] || die "xcodebuild $CONFIG MARKETING_VERSION is '${SETTING_VERSION:-empty}', expected $VERSION"
  [ "$SETTING_BUILD" = "$NEW_BUILD" ] || die "xcodebuild $CONFIG CURRENT_PROJECT_VERSION is '${SETTING_BUILD:-empty}', expected $NEW_BUILD"
  printf '  %s: MARKETING_VERSION=%s CURRENT_PROJECT_VERSION=%s\n' "$CONFIG" "$SETTING_VERSION" "$SETTING_BUILD"
done

step "4/10 Universal Release build (arm64 + x86_64) and Apple Development signing"
if ! xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$STAGE/DerivedData" CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' build 2>&1 | tee "$STAGE/build.log"; then
  die "Universal Release build failed. Log: $STAGE/build.log. project.yml/Pulse.xcodeproj contain the version bump; revert with: git checkout -- project.yml Pulse.xcodeproj"
fi
APP="$STAGE/DerivedData/Build/Products/Release/Pulse.app"
EXEC="$APP/Contents/MacOS/Pulse"
[ -d "$APP" ] || die "Release app not found at $APP (see $STAGE/build.log)"
[ -x "$EXEC" ] || die "Release executable missing at $EXEC"
ARCHS_FOUND="$(lipo -archs "$EXEC")"
case " $ARCHS_FOUND " in *" arm64 "*) ;; *) die "Release build is missing arm64 (lipo -archs: '$ARCHS_FOUND')";; esac
case " $ARCHS_FOUND " in *" x86_64 "*) ;; *) die "Release build is missing x86_64 (lipo -archs: '$ARCHS_FOUND')";; esac
printf '  architectures: %s\n' "$ARCHS_FOUND"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP" || die "codesign --force failed for $APP with identity '$IDENTITY'"
verify_signed "$APP" "staged app"
assert_meta "$APP" "$VERSION" "$NEW_BUILD" "staged app"
APP_EXEC_HASH="$(sha256_file "$EXEC")"
printf '  signed %s (build %s), executable sha256 %s\n' "$VERSION" "$NEW_BUILD" "$APP_EXEC_HASH"

step "5/10 Package ZIP + DMG and write checksum files"
ZIP_FILE="$ARTIFACTS/Pulse-$VERSION.zip"; DMG_FILE="$ARTIFACTS/Pulse-$VERSION.dmg"
ZIP_SHA="$ZIP_FILE.sha256"; DMG_SHA="$DMG_FILE.sha256"
ZIP_NAME="$(basename "$ZIP_FILE")"; DMG_NAME="$(basename "$DMG_FILE")"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP_FILE" || die "failed to create $ZIP_FILE"
ditto "$APP" "$STAGE/dmg-root/Pulse.app" || die "failed to stage Pulse.app for the DMG"
ln -s /Applications "$STAGE/dmg-root/Applications" || die "failed to create the Applications symlink in the DMG folder"
hdiutil create -volname "Pulse" -srcfolder "$STAGE/dmg-root" -ov -format UDZO "$DMG_FILE" || die "hdiutil create failed for $DMG_FILE"
(
  cd "$ARTIFACTS"
  shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256"
  shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
  shasum -a 256 -c "$ZIP_NAME.sha256"
  shasum -a 256 -c "$DMG_NAME.sha256"
) || die "checksum generation/verification failed in $ARTIFACTS"
grep -q "  $ZIP_NAME\$" "$ZIP_SHA" || die "$ZIP_SHA must contain the bare filename $ZIP_NAME"
grep -q "  $DMG_NAME\$" "$DMG_SHA" || die "$DMG_SHA must contain the bare filename $DMG_NAME"
printf '  %s\n  %s\n' "$ZIP_FILE" "$DMG_FILE"

step "6/10 Verify mounted DMG payload"
MOUNT_DIR="$STAGE/mnt"
ATTACH_OUT="$(hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$DMG_FILE")" || die "hdiutil attach failed for $DMG_FILE"
DMG_DEV="$(printf '%s\n' "$ATTACH_OUT" | awk '/^\/dev\// {print $1; exit}')"
[ -n "$DMG_DEV" ] || die "could not determine the mounted device from hdiutil output:"$'\n'"$ATTACH_OUT"
verify_signed "$MOUNT_DIR/Pulse.app" "DMG payload"
assert_meta "$MOUNT_DIR/Pulse.app" "$VERSION" "$NEW_BUILD" "DMG payload"
assert_hash "$MOUNT_DIR/Pulse.app" "$APP_EXEC_HASH" "DMG payload"
[ -L "$MOUNT_DIR/Applications" ] || die "DMG is missing the Applications symlink"
[ "$(readlink "$MOUNT_DIR/Applications")" = "/Applications" ] || die "DMG Applications symlink points to '$(readlink "$MOUNT_DIR/Applications")', expected /Applications"
hdiutil detach "$DMG_DEV" >/dev/null 2>&1 || die "hdiutil detach $DMG_DEV failed; unmount manually before retrying"
DMG_DEV=""
printf '  DMG verified (signature, %s/build %s, executable bytes, Applications link) and detached\n' "$VERSION" "$NEW_BUILD"

step "7/10 Verify ZIP payload (updater artifact)"
UNZIP_DIR="$STAGE/zip-check"
ditto -x -k "$ZIP_FILE" "$UNZIP_DIR" || die "failed to extract $ZIP_FILE"
verify_signed "$UNZIP_DIR/Pulse.app" "ZIP payload"
assert_meta "$UNZIP_DIR/Pulse.app" "$VERSION" "$NEW_BUILD" "ZIP payload"
assert_hash "$UNZIP_DIR/Pulse.app" "$APP_EXEC_HASH" "ZIP payload"
printf '  ZIP payload matches the signed app byte-for-byte (executable sha256 %s)\n' "$APP_EXEC_HASH"

step "8/10 Install $INSTALLED_APP"
if [ "$NO_INSTALL" = 1 ]; then
  printf '  skipped (--no-install)\n'
else
  install_app
fi

step "9/10 Commit, tag, push and create the GitHub release"
if [ "$NO_PUSH" = 1 ]; then
  printf '  skipped (--no-push). project.yml/Pulse.xcodeproj are bumped locally and uncommitted; artifacts: %s\n' "$ARTIFACTS"
  printf '  Commit manually with: git add -A -- project.yml Pulse.xcodeproj Pulse Tests scripts docs .trellis README.md && git commit -m "release: prepare Pulse %s"\n' "$VERSION"
else
  publish_release
fi

step "10/10 Verify published release via GitHub API"
if [ "$NO_PUSH" = 1 ]; then printf '  skipped (--no-push)\n'; else verify_published_release; fi

DMG_HASH="$(sha256_file "$DMG_FILE")"; ZIP_HASH="$(sha256_file "$ZIP_FILE")"
printf '\n================= Pulse %s (build %s) =================\n' "$VERSION" "$NEW_BUILD"
printf '  tag:          %s\n' "$TAG"
if [ "$PUBLISHED" = 1 ]; then
  printf '  release:      https://github.com/%s/releases/tag/%s\n' "$REPO_SLUG" "$TAG"
else
  printf '  release:      not published (--no-push)\n'
fi
printf '  notes:        %s\n' "$NOTES_FILE"
printf '  artifacts (kept outside the repo in %s):\n' "$ARTIFACTS"
printf '    %-30s sha256:%s\n' "$(basename "$DMG_FILE")" "$DMG_HASH"
printf '    %-30s sha256:%s\n' "$(basename "$ZIP_FILE")" "$ZIP_HASH"
printf '    %-30s sha256:%s\n' "$(basename "$DMG_SHA")" "$(sha256_file "$DMG_SHA")"
printf '    %-30s sha256:%s\n' "$(basename "$ZIP_SHA")" "$(sha256_file "$ZIP_SHA")"
if [ "$NO_INSTALL" = 1 ]; then
  printf '  installed:    skipped (--no-install)\n'
else
  printf '  installed:    %s (version %s, build %s, one running process)\n' "$INSTALLED_APP" "$VERSION" "$NEW_BUILD"
fi
printf '  staging:      %s\n\nDONE\n' "$STAGE"