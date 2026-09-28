# Architecture decisions (Phase 0)

## Native application boundary

Pulse is macOS-only and long-running. A checked-in Xcode app project gives a direct Run/debug path, app bundle metadata, signing settings, and future release packaging. `project.yml` keeps project generation reproducible; the generated project is committed so XcodeGen is not required to build. The minimum target is macOS 13, with Swift 6 language mode for compiler-checked concurrency boundaries.

In Phase 0, AppKit owned `NSApplicationDelegate`, `NSStatusItem`, a small menu, and a placeholder `NSWindow`. Phase 1 replaced the menu and window with a transient `NSPopover` hosting SwiftUI; see [the foundation implementation](phase1-foundation.md). `LSUIElement` keeps the app out of the Dock. The initial GitHub download build has no App Sandbox entitlement; Vault selection and file access policy must be revisited before any sandboxed distribution.

## Modules and persistence

No empty Swift package is created now. When provider normalization and Markdown parsing exist, move separable domain logic into a local package with useful unit tests. The app shell can then depend on that package, while AppKit/SwiftUI remain in the app target.

Vault Markdown will be the source of truth for tasks. A SQLite cache is unnecessary for the first implementation and would create a second state to reconcile; add one only if measured scan or query latency requires it. Ordinary preferences can use `UserDefaults`. API credentials must be stored in Keychain with a stable item reference in configuration, never in plist, project files, logs, or defaults.

## Release and trust

The first channel is a GitHub downloadable app. A useful release needs a working MVP, Developer ID signing, notarization, installation instructions, and a privacy review. Those are future gates, not claims about the current shell. No telemetry or update service is present.

## Open questions for implementation phases

- Codex app-server response shape and CLI discovery must be tested against supported installed versions.
- Provider-specific billing APIs may need elevated keys that users should not be asked to grant casually.
- Vault symlinks, cloud sync, and concurrent editors affect write safety; design and test them before enabling mutations.

See [reference analysis](01-reference-analysis.md), [provider design](04-provider-system-design.md), and [roadmap](06-mvp-roadmap.md).
