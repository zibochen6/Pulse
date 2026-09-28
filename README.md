# Pulse

Pulse is an early-stage, local-first macOS menu bar assistant for people who use AI services and Obsidian every day. The intended product brings AI usage status and Markdown tasks into one quick daily entry point.

**Current state:** Phase 1 Foundation is a buildable menu bar app. The Pulse icon always shows `--%` beside it to indicate that usage is not connected. Clicking it opens a native popover with Usage and Tasks placeholders and basic Settings. It does not yet read AI usage, request API credentials, or access an Obsidian vault. This repository is not a usable MVP or downloadable release yet.

## Build and run

Requirements: macOS 13 or newer and Xcode 26.6 or a compatible Xcode version.

1. Open `Pulse.xcodeproj` in Xcode.
2. Select the `Pulse` scheme and **My Mac**, then Run.
3. Click the Codex-style icon in the menu bar to open or close Pulse. Click outside to dismiss the popover; choose **Quit Pulse** in Settings to exit. Pulse has no Dock icon.

Command-line build:

```sh
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/PulseDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/PulseDerivedData CODE_SIGNING_ALLOWED=NO test
```

`project.yml` is the [XcodeGen](https://github.com/yonaskolb/XcodeGen) source for the checked-in Xcode project. XcodeGen is only needed if you change project structure: run `xcodegen generate` and commit the updated `.xcodeproj` together with `project.yml`. The app has `App`, `Core`, `Features`, and `UI` source directories; the unit tests use a simulated login item service.

## Current settings

**Launch at login** requests registration through macOS Login Items. Pulse shows the actual system status separately from the saved preference; macOS may require approval in System Settings or reject registration from a development build. **Show Pulse name in menu bar** adds “Pulse” before the always-visible `--%` readout. Both preferences start off and are stored in UserDefaults. Automated tests never modify the machine's Login Items.

## Direction

- **AI status:** Codex first, then provider-specific capabilities for OpenAI API, DeepSeek, GLM, OpenRouter, and custom endpoints. A balance and a rate-limit window will be displayed as different kinds of information.
- **Obsidian tasks:** the user chooses a Vault. Pulse will scan Markdown tasks without assuming folder names and will preserve the source note as the source of truth.
- **Privacy:** the app runs locally; future API secrets belong in macOS Keychain. This foundation stores only the two preferences above, with no keys or Vault data. No analytics are present.

See [Phase 1 foundation](docs/phase1-foundation.md), [menu bar status requirements](docs/08-menu-bar-status-requirements.md), [the roadmap](docs/06-mvp-roadmap.md), [architecture decisions](docs/02-architecture-decisions.md), and [reference analysis](docs/01-reference-analysis.md). Contributions and issue reports are welcome once the first integration milestones are open. Please do not post API keys or private notes in issues.

## 中文简介

Pulse 计划成为一个本地优先的 macOS 菜单栏工作入口，集中查看 AI 服务额度和 Obsidian Markdown 待办。目前已有原生菜单栏弹窗与基础设置，尚未实现额度查询或 Vault 读写。后续阶段见 [路线图](docs/06-mvp-roadmap.md)。

## License

MIT. See [LICENSE](LICENSE). The menu bar icon is copied from `codex-usage-status` under MIT; see [third-party notices](THIRD_PARTY_NOTICES.md) for attribution and license terms. No reference application source code is copied into Pulse.
