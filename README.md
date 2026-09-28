# Pulse

Pulse is an early-stage, local-first macOS menu bar assistant for people who use AI services and Obsidian every day. The intended product brings AI usage status and Markdown tasks into one quick daily entry point.

**Current state:** Phase 0 is a buildable menu bar shell. It shows a Pulse icon, an **Open Pulse** placeholder window, and **Quit Pulse**. It does not yet read AI usage, request API credentials, or access an Obsidian vault. This repository is not a usable MVP or downloadable release yet.

## Build and run

Requirements: macOS 13 or newer and Xcode 26.6 or a compatible Xcode version.

1. Open `Pulse.xcodeproj` in Xcode.
2. Select the `Pulse` scheme and **My Mac**, then Run.
3. Look for the waveform icon in the menu bar. Choose **Open Pulse** for the placeholder or **Quit Pulse** to exit.

Command-line build:

```sh
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/PulseDerivedData CODE_SIGNING_ALLOWED=NO build
```

`project.yml` is the [XcodeGen](https://github.com/yonaskolb/XcodeGen) source for the checked-in Xcode project. XcodeGen is only needed if you change project structure: run `xcodegen generate` and commit the updated `.xcodeproj` together with `project.yml`.

## Direction

- **AI status:** Codex first, then provider-specific capabilities for OpenAI API, DeepSeek, GLM, OpenRouter, and custom endpoints. A balance and a rate-limit window will be displayed as different kinds of information.
- **Obsidian tasks:** the user chooses a Vault. Pulse will scan Markdown tasks without assuming folder names and will preserve the source note as the source of truth.
- **Privacy:** the planned app runs locally; future API secrets belong in macOS Keychain. This Phase 0 shell stores no keys or Vault data. No analytics are present.

See [the roadmap](docs/06-mvp-roadmap.md), [architecture decisions](docs/02-architecture-decisions.md), and [research index](docs/01-reference-analysis.md). Contributions and issue reports are welcome once the first integration milestones are open. Please do not post API keys or private notes in issues.

## 中文简介

Pulse 计划成为一个本地优先的 macOS 菜单栏工作入口，集中查看 AI 服务额度和 Obsidian Markdown 待办。目前仓库仅包含可启动的工程外壳与技术研究，尚未实现额度查询或 Vault 读写。后续阶段见 [路线图](docs/06-mvp-roadmap.md)。

## License

MIT. See [LICENSE](LICENSE). The `codex-usage-status` project informed the architecture research; no reference source code is copied into this Phase 0 app.
