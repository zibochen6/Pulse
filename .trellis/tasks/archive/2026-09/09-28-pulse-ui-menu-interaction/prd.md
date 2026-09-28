# Pulse UI layout and menu interaction

## Goal

Make the menu bar popover a compact daily entry point for AI usage and tasks, with settings available on a separate page inside the same popover and predictable delayed pointer dismissal.

## Background

- Pulse is a macOS 13+ menu bar app with one AppKit `NSStatusItem`, one transient `NSPopover`, and SwiftUI content.
- `PulseAppDelegate` owns the shared `AppConfig` and `UsageController`. The status item and `UsageView` consume the same Codex usage state.
- The current Home shows Usage, a Tasks placeholder, and all settings in one scrolling page. The popover closes on a second status item click or an outside interaction.
- The user approved the preceding implementation plan and approved creating this Trellis task. They chose settings navigation inside the popover and explanation sections for future integrations.

## Requirements

1. Home presents a Pulse icon/name header with a Settings action, followed by compact Usage and Tasks sections. General settings and Quit do not appear on Home.
2. Codex Usage retains real values, all reported quota windows, reset and update times, refresh, and clear loading/unavailable/error states. Other providers remain an honest empty state with an Add Provider entry point; no fabricated data is shown.
3. Tasks has a clear Obsidian disconnected state and Connect entry point; it must not show sample tasks as if they were user data.
4. Settings is a separate page in the same popover with a return action. It contains General preferences and current Login Items feedback, Providers and Tasks coming-soon explanations, About version and third-party notices, and Quit.
5. The status item click still toggles the popover and outside clicks still dismiss it. While shown, pointer presence over either the status button or popover keeps it open. After leaving both, it closes after 400 ms unless the pointer re-enters. Page navigation, refresh, scrolling, and internal controls do not themselves dismiss it.
6. Keep native macOS light/dark styling, dense readable hierarchy, menu bar Codex icon/readout, current refresh behavior, and existing provider internals.
7. Update README and add `docs/ui-layout-refactor.md`. Commit with `refactor: redesign Pulse menu layout and interactions`; do not push.

## Acceptance Criteria

- [ ] Home has Header → Usage → Tasks, no inline preferences or Quit, and the gear opens an in-popover Settings page with a back action.
- [ ] Codex values and error messages remain accurate; Add Provider and Connect Obsidian open the relevant Settings explanation without enabling integrations.
- [ ] Settings controls retain existing persistence and actual macOS Login Items status handling; About shows a real bundle version or “Development build” and the bundled third-party notices.
- [ ] Click-to-toggle and outside-click dismissal work; pointer exit from both regions schedules a 400 ms close that is canceled by re-entry; internal interaction does not close the popover.
- [ ] Existing tests plus focused hover state and light/dark rendering tests pass; Debug build succeeds; manual interaction checks are recorded with any observation limits.
- [ ] Diff contains no Codex data retrieval changes and is committed locally with the requested message, without pushing.

## Out of Scope

- New AI providers, Obsidian connection or task data, database, network integrations, and changes to the Codex app-server request/decoder.
