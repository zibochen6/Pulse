# Pulse

Pulse is an early-stage, local-first macOS menu bar assistant for people who use AI services and Obsidian every day. The intended product brings AI usage status and Markdown tasks into one quick daily entry point.

**Current state:** Pulse is a buildable menu bar app with Codex usage and optional 88VIP balance integrations. It reads rate-limit windows from a locally installed, signed-in Codex CLI and can query a user-configured 88VIP account balance. The menu bar remains Codex-only; the popover header shows both compact statuses. Click either status for Usage details; Settings is another page in the same popover. Obsidian is not connected. This repository is not a downloadable MVP release yet.

## Build and run

Requirements: macOS 13 or newer and Xcode 26.6 or a compatible Xcode version.

1. Open `Pulse.xcodeproj` in Xcode.
2. Select the `Pulse` scheme and **My Mac**, then Run.
3. Sign in to Codex if needed, then click the Codex icon in the menu bar. The Home popover shows Tasks first; click its compact Codex status for quota details, or the gear for Settings. Both pages return to Home. Click the menu bar item again or click outside to dismiss the popover. It also closes 400 ms after the pointer leaves both it and the menu bar item; returning the pointer cancels that close. Choose **Quit Pulse** in Settings to exit. Pulse has no Dock icon.

Command-line build:

```sh
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/PulseDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/PulseDerivedData CODE_SIGNING_ALLOWED=NO test
```

After rebuilding, quit any running Pulse instance and launch the new build. A menu bar app can keep displaying the previous icon and readout until its process restarts.

`project.yml` is the [XcodeGen](https://github.com/yonaskolb/XcodeGen) source for the checked-in Xcode project. XcodeGen is only needed if you change project structure: run `xcodegen generate` and commit the updated `.xcodeproj` together with `project.yml`. The app has `App`, `Core`, `Features`, and `UI` source directories. Unit tests use synthetic usage responses, a mock usage provider, and a simulated login item service. The test scheme disables live Codex refresh in its app host, so tests do not query a real account.

## Current settings

**Launch at login** requests registration through macOS Login Items. Pulse shows the actual system status separately from the saved preference; macOS may require approval in System Settings or reject registration from a development build. **Show Pulse name in menu bar** adds “Pulse” before the Codex readout. Both preferences start off and are stored in UserDefaults. Automated tests never modify the machine's Login Items.

## Codex usage

Pulse launches the local Codex app-server and requests its ChatGPT rate-limit state. With one reported window, the menu bar and Home summary show only the remaining percentage, such as `98%`; with multiple windows, they use short labels, such as `5h 66% 7d 63%`. Loading, unavailable data, and errors never become a fabricated percentage. The separate Usage page gives window, reset, update, and refresh details. Pulse refreshes at startup and while running. It reads no Codex authentication files and stores no usage credentials.

If the app cannot find Codex, install or launch Codex and check that its CLI works in a terminal. Development builds can also use the `CODEX_BIN` environment variable to point to the executable. A failed explicit override is reported as an error. The local CLI protocol and app bundle layout can change, so please report reproducible failures without sharing account secrets.

## 88VIP balance

Open **Settings → Providers**, enter your 88VIP API key, and select **Save key**. Pulse stores the key only in your macOS Keychain. It queries 88API's documented billing subscription and usage endpoints, calculates the remaining balance in USD, and shows it beside Codex in the popover. The full Usage page includes the limit, used amount, remaining amount, available expiry, update time, and a manual refresh action.

88VIP refreshes at launch and every ten minutes. Opening the popover refreshes it only after the last result becomes stale. Missing keys, invalid keys, rate limits, unsupported billing endpoints, network problems, and malformed responses are shown as clear states; Pulse never converts a USD value to another currency or fabricates a remaining balance.

## Direction

- **AI status:** Codex and 88VIP are connected. Provider-specific capabilities for OpenAI API, DeepSeek, GLM, OpenRouter, and custom endpoints are planned. A balance and a rate-limit window are displayed as different kinds of information.
- **Obsidian tasks:** the user chooses a Vault. Pulse will scan Markdown tasks without assuming folder names and will preserve the source note as the source of truth.
- **Privacy:** the app runs locally. 88VIP API keys are stored in macOS Keychain; ordinary preferences use UserDefaults. Pulse stores no Vault data and has no analytics.

See [UI layout and interaction](docs/ui-layout-refactor.md), [Codex integration](docs/phase2-codex-provider.md), [Phase 1 foundation](docs/phase1-foundation.md), [menu bar status requirements](docs/08-menu-bar-status-requirements.md), [the roadmap](docs/06-mvp-roadmap.md), [architecture decisions](docs/02-architecture-decisions.md), and [reference analysis](docs/01-reference-analysis.md). Contributions and issue reports are welcome. Please do not post API keys or private notes in issues.

## 中文简介

Pulse 计划成为一个本地优先的 macOS 菜单栏工作入口，集中查看 AI 服务额度和 Obsidian Markdown 待办。目前已接入本机 Codex CLI 与可选的 88VIP USD 余额：菜单栏只显示 Codex，弹窗可显示两者并查看详情；Vault 读写和其他 Provider 尚未实现。后续阶段见 [路线图](docs/06-mvp-roadmap.md)。

## License

MIT. See [LICENSE](LICENSE). The menu bar icon is copied from `codex-usage-status` under MIT; see [third-party notices](THIRD_PARTY_NOTICES.md) for attribution and license terms. No reference application source code is copied into Pulse.
