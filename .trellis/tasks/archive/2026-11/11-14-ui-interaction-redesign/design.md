# Design and boundaries

Approved PRD supersedes old 360×380 and in-popover settings clauses. Data safety, IME, async draft identity, real-value and opaque-root contracts remain.

## Architecture
- AppDelegate owns config, providers, tasks, updates, LocalTaskPresentation and singleton SettingsWindowController. SettingsPresentation owns in-memory per-service drafts and selected category. Home observes injected state.
- PopoverPage: Home, usage(ProviderID), tagManagement. Settings navigation is independent; open(destination:, provider:) deep-links. Register window-active before closing popover to avoid updater idle gap.
- Provider display maps configuration plus existing UsageRefreshState. Stored key is not verified connection. No extra network requests; preserve credentialsDidChange invalidation.
- Keep stable draft IDs/versions and per-list drafts. Add hasUnsavedEdits separate from active focus. Tag delete detects affected drafts and routes back before deletion; no orphan draft dictionary entries.
- Aggregate interaction holds by source (editor, menu object, drag session); use existing hover controller. Observe native NSMenu begin/end tracking. NSDraggingSource bridge provides reliable end/cancel; dropExited clears only insertion marker. Keep geometry-based preview and storage commit.

## Visual and motion system
400×520 main surface, 720×560 Settings with ~168pt sidebar. Opaque adaptive root, lifted cards, restrained borders. Accent #6D5CE8 light / #AC9EFF dark; neutral #F7F7FB light / #18191F dark. Violet/mint/apricot/sky tag colors derive deterministically from UUID, no migration. Adaptive semantic text and real provider icons. Values wrap without truncation. Capped pill labels have full-name help.

Separate ease-out color/opacity from spatial springs, macOS13 APIs only. Stable toolbar; page host ends old native editing and fades an in-memory noninteractive outgoing snapshot, invalidating prior snapshot on rapid navigation. Never retain outgoing live fields. Reduce Motion omits scale/offset, including press feedback. Add/options labels are explicit and hit areas stable.

## Settings and update safety
Credential drafts live only in settings session memory and, on explicit save, Keychain. Category/window switches preserve drafts; successful matching save or explicit cancel clears. Close does not quit or discard. Native edit commands retain responder chain. Auto install sees visible settings, hidden drafts and writes. UI restart/quit routes to AppDelegate preflight before UpdateController installer starts; cancelled action does not install. No draft confirmation on ordinary close.

## Localization and demonstration
English source plus zh-Hans localized resources/helper, macOS13 compatible. Preserve interpolation/plurals, identifiers, user content and data/error identities. Final localization pass has one owner after parallel edits. Demo/render harness disables live providers, real secrets, updates and real tasks; renders real product views, labels samples and outputs new docs/media/ui-redesign assets.

## Compatibility
No persistence migration, new dependencies, provider API change or release. App stays accessory/no Dock icon. Generate Xcode project from project.yml after adding files. Do not replace installed build or touch unrelated untracked work. Reverting UI does not require data rollback.
