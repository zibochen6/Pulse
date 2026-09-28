# Pulse Foundation and Architecture Research

## Goal

Establish a buildable, launchable native macOS menu bar project and evidence-based documentation for a local-first AI usage and Obsidian task assistant. This is an engineering foundation, not a complete feature release.

## Confirmed context

- Pulse's public GitHub repository is empty. The local Pulse directory contained Trellis scaffolding but was initially nested in another Git working tree; it now has its own empty Git repository with `origin` set to `https://github.com/zibochen6/Pulse.git`.
- Xcode 26.6 and Swift 6.3 are available. `codex-usage-status` is cloned locally and has a native Swift macOS implementation under `macos/CodexUsageStatus/`.
- A private local Obsidian vault is available for read-only validation. It has `.obsidian`, multiple note areas, and many ordinary checkboxes. A `Daily/` directory exists while the core Daily Notes plugin is disabled, so folder names are not evidence of enabled workflow.
- The user selected GitHub download distribution, MIT licensing, English-first public documentation with a Chinese summary, optional Obsidian onboarding, and ordinary checkbox writes for the first Obsidian release.

## Requirements

1. Create a native Xcode macOS 13+ app with a minimal AppKit menu bar entry, placeholder window, and Quit action. Plan SwiftUI for future settings/content. Do not implement production provider or Vault behavior now.
2. Add appropriate `.gitignore`, MIT `LICENSE`, English-first README with a Chinese summary, and `docs/`.
3. Document the reference app's lifecycle, menu bar, UI, refresh, Codex data path, models, error handling, useful reuse, and unsuitable patterns in `docs/01-reference-analysis.md`.
4. Document architecture tradeoffs in `docs/02-architecture-decisions.md` and Obsidian discovery, structures, task scope, safe writes, watching, and conflict behavior in `docs/03-obsidian-integration-research.md`. Use the private vault only as a read-only sample; never publish its path or note content.
5. Document a capability-aware provider contract, configuration, Keychain storage, refresh, errors, and verified API boundaries in `docs/04-provider-system-design.md`.
6. Document a five-minute first-run flow in `docs/05-user-flow.md`, phased acceptance and risks in `docs/06-mvp-roadmap.md`, and a portfolio/community launch preparation plan in `docs/07-community-launch-plan.md`.
7. Validate the app build and launch, review source-backed documentation, inspect the independent repository diff, commit with the exact message `chore: initialize Pulse project and add architecture research`, and push to `origin/main`.

## Out of scope

- Full usage fetching, provider integrations, Keychain writes, Vault modification, complete UI, SQLite, telemetry, signing/notarization, releases, or community posting.
- Treating the user's Vault layout as a universal layout or including private note text in source control.

## Acceptance Criteria

- [ ] Pulse is an independent Git repository; no parent project changes are staged or committed.
- [ ] The Xcode app builds for macOS and launches as a menu bar app with a working Quit action.
- [ ] README accurately explains current capabilities and build/run steps; required project metadata is present.
- [ ] Documents 01–07 cover all required topics, distinguish confirmed capabilities from future work, and cite local source paths or authoritative external references.
- [ ] Private Vault inspection is read-only; no private absolute path or note content appears in public files.
- [ ] The final staged diff is reviewed, committed with the required message, and pushed to the empty Pulse remote.
