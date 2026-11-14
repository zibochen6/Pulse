# Pulse UI, interaction and motion redesign

## Goal and approved decisions
Deliver an elegant, joyful native macOS daily AI-status and to-do utility with clear controls and real interactions suitable for promotion. The user approved the complete plan and requested implementation on 2026-11-14; no further planning approval is needed.

- Native premium surfaces with soft violet/blue, mint and apricot accents.
- Fixed 400 × 520 menu-bar popover and singleton 720 × 560 Settings window with categories.
- Preserve 180 ms pointer departure dismissal, 300 ms/presentation opening guard; protect menus, dragging and editing.
- English and Simplified Chinese following system language, including promotional assets.
- Keep macOS 13, local schema 1, provider APIs, native currency semantics, Keychain isolation and refresh cadence.

## Requirements and acceptance
1. Shared hierarchy: 16 pt content insets, 8 pt rhythm, 15 pt task text, >=12 pt auxiliary text; adaptive surfaces, violet accent, soft colored tag identities, clear primary/secondary/destructive actions. Popover root stays opaque and fixed-size.
2. Home: brand, meaningful provider summaries, tags and tasks. Missing configuration offers Connect, not failure. Provider clicks open that provider; real values wrap without cutting decimals. Task completion stays in place; explicit Add task and Add actions.
3. Tags: pinned Todo, horizontal custom tags, fixed add/all-tags, overflow affordances, selected-tag ellipsis with rename/delete/move. Searchable manager with full names/counts and CRUD/reorder shared with Settings. No count cap: verify 0/1/10/50/100. Duplicates offer existing destination, no silent no-op. Delete confirms tasks move to Todo and is blocked by affected unsaved drafts, with Return to draft. Never overwrite another draft. Edge autoscroll and keyboard/button reorder.
4. Settings: General, AI services, Lists & tags, Updates, About. Singleton, deep links, ordinary reopen restores category; close does not quit. Credential forms open on request and use Save and verify / Replace key / Disconnect. Stored key alone cannot claim Connected. Cmd+, opens Settings, Cmd+W closes window, Cmd+Q quits. Preserve unfinished input across category/window changes in memory.
5. Motion: native panel open/close only; hover/press 120/90 ms without bounce; page body ~200 ms/8 pt with old noninteractive snapshot fade; tag selection 180 ms, composer 200 ms, completion 180 ms, reorder 240 ms mild spring. Preserve input lifecycle and interruptibility. Reduce Motion removes geometry and keeps short fade. No perpetual decorations or per-row entrance delays.
6. Native menu tracking and full drag sessions independently hold the popover; cancellation releases only its own hold. Preserve hover state-machine semantics. External drop cancels without exporting/removing tags.
7. App-owned task presentation and existing controllers shared across windows. Auto-install only when both surfaces closed, no unsaved task/settings drafts and no pending writes. Explicit restart/quit checks before installer starts; Continue editing or explicit Discard. Closing Settings retains drafts without prompting.
8. Localize interface, dynamic/error/accessibility text. Todo remains a stable reserved title; user content never translated.
9. Promotion: isolated sample data with real components/interaction, bilingual Home/Settings screenshots and 15–20s real-interaction demo. Label samples. Update README and obsolete launch notes; do not publish externally or overwrite untracked docs/images.

## Out of scope
New providers, sync, task schema changes, monetization, telemetry, signing/notarization and public release; replacing NSPopover; destructive changes to user data.

## Authorized delivery extension — 2026-11-14

After reviewing the implemented preview, the user explicitly requested commit,
publication and updating the locally installed application. This supersedes the
earlier exclusion of release delivery. Use the existing Apple Development
preview channel and `scripts/release.sh` for version 0.1.8/build 12, retain the
existing team, and publish the verified universal DMG/ZIP plus checksums. Keep
unrelated `.workbuddy/` and `docs/images/` out of commits. Respect graceful-quit
cancellation, preserve a unique backup, and verify the installed executable and
published release assets. Developer ID/notarization remains outside this scope.

## Baseline
Debug build and 79 existing UI/tag/popover tests passed. Native desktop access timed out during planning, so actual visual/mouse acceptance is still required and must be reported honestly if unavailable. Preserve pre-existing untracked .workbuddy/ and docs/images/.
