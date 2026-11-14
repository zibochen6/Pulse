#!/usr/bin/env bash
# Isolated release safety regressions. No real app, signing, network or UI calls.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_SCRIPT="$SCRIPT_DIR/../release.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pulse-release-safety.XXXXXX")"
trap 'rm -r "$TEST_ROOT"' EXIT
# Load helper definitions only, stopping before the release entry point.
awk '/^trap cleanup EXIT$/ { exit } { print }' "$RELEASE_SCRIPT" > "$TEST_ROOT/functions.sh"
source "$TEST_ROOT/functions.sh"
PASS_COUNT=0

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_fails() { if ( "$@" ) >/dev/null 2>&1; then fail "expected failure: $*"; fi; }

# All external commands used by quit/restore/signature helpers are stubbed.
pgrep() { [ -f "$CASE_DIR/running" ] || return 1; printf '4242\n'; }
osascript() {
  printf '%s\n' "$*" >> "$CASE_DIR/quit-calls"
  case "$QUIT_RESULT" in
    accepted) rm "$CASE_DIR/running" ;;
    declined) return 1 ;;
    pending) return 0 ;;
    *) fail "unexpected quit result" ;;
  esac
}
sleep() { SECONDS=$((SECONDS + 16)); }
kill() { printf '%s\n' "$*" >> "$CASE_DIR/signal-calls"; return 99; }
ditto() { printf '%s\n' "$*" >> "$CASE_DIR/copy-calls"; cp -R "$1" "$2"; }
open() { printf '%s\n' "$*" >> "$CASE_DIR/open-calls"; }
codesign() {
  if [ "$1" = --verify ]; then return "$SIGNATURE_RESULT"; fi
  case " $* " in *' --verbose=2 '*) ;; *) fail "signer inspection requires --verbose=2" ;; esac
  printf 'Identifier=%s\nAuthority=%s\nTeamIdentifier=%s\n' \
    "$SIGNATURE_IDENTIFIER" "$SIGNATURE_AUTHORITY" "$SIGNATURE_TEAM"
}
security() { printf '  1) TESTIDENTITY "%s"\n' "$SIGNATURE_AUTHORITY"; }

run_case() {
  local name="$1"
  (
    CASE_DIR="$TEST_ROOT/$name"
    mkdir -p "$CASE_DIR"
    INSTALLED_APP="$CASE_DIR/Installed.app"
    BACKUP_APP="$CASE_DIR/Backup.app"
    BACKUP_ROOT="$CASE_DIR/backups"
    mkdir -p "$INSTALLED_APP" "$BACKUP_APP"
    printf 'new\n' > "$INSTALLED_APP/payload"
    printf 'old\n' > "$BACKUP_APP/payload"
    QUIT_RESULT=accepted
    IDENTITY='Apple Development: Release Test (TESTID)'
    SIGNATURE_AUTHORITY="$IDENTITY"
    SIGNATURE_TEAM=9Y4B7WBUU2
    SIGNATURE_IDENTIFIER=dev.zibochen.Pulse
    SIGNATURE_RESULT=0
    NO_INSTALL=0
    NO_PUSH=0
    unset PULSE_TEAM_ID PULSE_SIGN_IDENTITY
    "$name"
    [ ! -e "$CASE_DIR/signal-calls" ] || fail 'a termination signal was sent'
  )
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$name"
}

already_stopped_does_not_request_quit() {
  quit_pulse
  [ ! -e "$CASE_DIR/quit-calls" ] || fail 'quit requested for an absent app'
}

accepted_quit_waits_for_exit() {
  touch "$CASE_DIR/running"
  quit_pulse
  [ ! -e "$CASE_DIR/running" ] || fail 'app did not stop'
  [ -e "$CASE_DIR/quit-calls" ] || fail 'missing graceful quit request'
}

declined_quit_is_not_forced() {
  touch "$CASE_DIR/running"
  QUIT_RESULT=declined
  assert_fails quit_pulse
  [ -e "$CASE_DIR/running" ] || fail 'cancelled app was stopped'
}

timed_out_quit_is_not_forced() {
  touch "$CASE_DIR/running"
  QUIT_RESULT=pending
  assert_fails quit_pulse
  [ -e "$CASE_DIR/running" ] || fail 'pending app was stopped'
}

assert_restore_preserves_both_apps() {
  assert_fails restore_previous_app
  [ "$(cat "$INSTALLED_APP/payload")" = new ] || fail 'running app was replaced'
  [ "$(cat "$BACKUP_APP/payload")" = old ] || fail 'backup was modified'
  [ ! -e "$CASE_DIR/copy-calls" ] || fail 'restore copied despite cancelled quit'
}

declined_rollback_preserves_running_app() {
  touch "$CASE_DIR/running"
  QUIT_RESULT=declined
  assert_restore_preserves_both_apps
}

timed_out_rollback_preserves_running_app() {
  touch "$CASE_DIR/running"
  QUIT_RESULT=pending
  assert_restore_preserves_both_apps
}

accepted_rollback_restores_backup() {
  touch "$CASE_DIR/running"
  restore_previous_app
  [ "$(cat "$INSTALLED_APP/payload")" = old ] || fail 'backup not restored'
  [ "$(cat "$BACKUP_APP/payload")" = old ] || fail 'backup not retained'
  [ -e "$CASE_DIR/open-calls" ] || fail 'restored app not relaunched'
}

repeated_backups_preserve_prior_copy() {
  local first second
  first="$(new_backup_path 0.1.7 11)"
  mkdir "$first"
  printf 'previous backup\n' > "$first/payload"
  second="$(new_backup_path 0.1.7 11)"
  [ "$first" != "$second" ] || fail 'backup path reused'
  [ -d "$(dirname "$second")" ] || fail 'second directory not reserved'
  [ "$(cat "$first/payload")" = 'previous backup' ] || fail 'prior backup overwritten'
  [[ "$first" =~ Pulse-0\.1\.7-11-[0-9]{8}T[0-9]{6}Z\. ]] || fail 'backup lacks timestamp'
}

normal_publish_options_are_allowed() { validate_release_options; }
uninstalled_build_cannot_publish() { NO_INSTALL=1; assert_fails validate_release_options; }
uninstalled_local_build_is_allowed() { NO_INSTALL=1; NO_PUSH=1; validate_release_options; }
different_team_override_is_rejected() { PULSE_TEAM_ID=OTHERTEAM; assert_fails validate_release_options; }
matching_team_override_is_allowed() { PULSE_TEAM_ID=9Y4B7WBUU2; validate_release_options; }
trusted_signature_is_accepted() { verify_signed "$INSTALLED_APP" test; }
wrong_bundle_identifier_is_rejected() { SIGNATURE_IDENTIFIER=dev.other.App; assert_fails verify_signed "$INSTALLED_APP" test; }
wrong_signature_team_is_rejected() { SIGNATURE_TEAM=OTHERTEAM; assert_fails verify_signed "$INSTALLED_APP" test; }
other_signing_channel_is_rejected() {
  SIGNATURE_AUTHORITY='Developer ID Application: Release Test (TESTID)'
  IDENTITY="$SIGNATURE_AUTHORITY"
  assert_fails verify_signed "$INSTALLED_APP" test
  PULSE_SIGN_IDENTITY="$IDENTITY"
  assert_fails resolve_identity
}
invalid_signature_is_rejected() { SIGNATURE_RESULT=1; assert_fails verify_signed "$INSTALLED_APP" test; }

for test_case in \
  already_stopped_does_not_request_quit accepted_quit_waits_for_exit \
  declined_quit_is_not_forced timed_out_quit_is_not_forced \
  declined_rollback_preserves_running_app timed_out_rollback_preserves_running_app \
  accepted_rollback_restores_backup repeated_backups_preserve_prior_copy \
  normal_publish_options_are_allowed uninstalled_build_cannot_publish \
  uninstalled_local_build_is_allowed different_team_override_is_rejected \
  matching_team_override_is_allowed trusted_signature_is_accepted \
  wrong_bundle_identifier_is_rejected wrong_signature_team_is_rejected \
  other_signing_channel_is_rejected invalid_signature_is_rejected; do
  run_case "$test_case"
done

printf '%s release safety checks passed.\n' "$PASS_COUNT"
