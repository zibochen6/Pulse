# Pulse Phase 1 Menu Bar Foundation

## Goal

Make Pulse a stable macOS menu bar application whose popover clearly presents the future Usage and Tasks areas and a working Settings area. The foundation should be easy to extend without adding business integrations now.

## Background

- Phase 0 is a clean, buildable macOS 13+ Swift 6 XcodeGen app on `main` with `LSUIElement=YES`.
- Its AppKit status item currently opens a placeholder `NSWindow`; there is no SwiftUI view, configuration model, or test target.
- The user approved the Phase 1 implementation plan and clarified that menu bar stability takes priority if a setting proves complex. During implementation, the user supplied a reference screenshot and asked for an always-visible icon plus status readout in the menu bar, then specifically requested the same Codex icon as the reference app. Icons for future API providers are a later phase.
- The user supplied a local export of the previous `codex-usage-status` improvement session to inform Pulse's future display design. Its lessons belong in public planning without publishing private session content.

## Requirements

1. Keep Pulse menu bar only, without a Dock icon. Replace the menu and placeholder window with an `NSStatusItem` that shows the reference project's Codex icon and adjacent status readout at all times, and toggles one native `NSPopover`, which closes when clicking elsewhere. Provide a reliable Quit action. Before a real usage source exists, show an explicit `--%` placeholder, never a fabricated percentage. Preserve the reused icon's license notice.
2. Build a SwiftUI `HomeView` with Usage, Tasks, and Settings sections. Usage and Tasks must state they are not connected rather than show fabricated data.
3. Organize the app source under `App`, `Core`, `Features`, and `UI`; do not add empty modules or an unnecessary package.
4. `AppConfig` persists the user's requested login launch setting and a basic menu bar title preference in UserDefaults. Both default off. Use `SMAppService.mainApp` for real login item registration and report actual macOS status, including approval and failure states. Login item failures must not prevent the status item and popover from working.
5. Keep code compatible with macOS 13 and Swift 6, avoid force unwraps, and add focused unit tests without modifying the host's real login items.
6. Update README, add `docs/phase1-foundation.md`, and reconcile the Phase 1 roadmap description.
7. Record the earlier menu bar iteration's product lessons for future Codex and Provider phases: native template icon, remaining percentage, one-window compact readout, labels only for multiple windows, real window detection, clear refresh/error states, and source-specific icons later.

## Acceptance Criteria

- [ ] Debug app builds and launches; a status item appears and no Dock icon is shown.
- [ ] Menu bar directly shows the reference Codex icon plus `--%` no-data readout; clicking it opens/closes one popover; clicking outside closes it; Settings can quit Pulse. Icon attribution is included.
- [ ] Usage and Tasks display explicit placeholders; no provider, Codex, Obsidian, or database code is added.
- [ ] Preferences survive a new `AppConfig` instance; the login setting attempts registration/unregistration via an injectable service, and the UI distinguishes requested preference from actual system status.
- [ ] Login item failure or system approval requirement is visible without breaking the app.
- [ ] Automated build and unit tests pass; manual launch smoke results and any environment limitation are documented.
- [ ] README, phase document, roadmap, generated Xcode project, and `project.yml` agree; complete diff reviewed; commit uses `feat: implement Pulse menu bar foundation`.
- [ ] The prior iteration is reflected in architecture/roadmap research without including private paths, account details, or the session export.

## Out of Scope

AI Provider, Codex API, other API/service icons, Obsidian, database, helper login agents, background polling, polished production UI, release packaging, and remote push.
