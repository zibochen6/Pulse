# Pulse

Pulse is an early-stage, local-first macOS menu bar assistant for people who use AI services every day. The intended product brings AI usage status and daily to-dos into one quick daily entry point.

**Current state:** Pulse is a buildable menu bar app with Codex usage, optional 88VIP and DeepSeek balance integrations, and native to-do lists with one tag per task, independent tag creation, quick entry, deletion undo, optional daily repeat, and visible completed tasks. It reads rate-limit windows from a locally installed, signed-in Codex CLI and can query user-configured 88VIP and DeepSeek account balances. The menu bar remains Codex-only; the popover header shows all three compact statuses, left aligned and wrapped when needed. Click any status for Usage details; Settings is another page in the same popover. A development-signed preview is available on GitHub.

## Download and install

Download [Pulse 0.1.6](https://github.com/zibochen6/Pulse/releases/tag/v0.1.6)
for macOS 13 or newer (Apple Silicon and Intel). Open the DMG and drag Pulse
to Applications. Quit the previous Pulse instance before replacing it, then
launch `/Applications/Pulse.app`; its settings and task storage are retained.
The release publishes `Pulse-0.1.6.dmg` with a SHA-256 checksum for manual
installs, plus `Pulse-0.1.6.zip` and its checksum for the in-app updater; the
DMG and ZIP contain the same signed app.

This preview is signed with an Apple Development certificate, **not Developer ID
signed or notarized**. macOS may block first launch. If you trust the downloaded
build, use the available **Open Anyway** option in System Settings → Privacy &
Security after attempting to launch; follow [Apple's guidance](https://support.apple.com/102445)
and do not disable Gatekeeper. Source builds
remain available below. See [0.1.6 release notes](docs/releases/0.1.6.md) for
changes and current limits.

## Automatic updates

Pulse 0.1.3 and later check the public GitHub latest-release feed about ten
seconds after launch and every six hours while running. Settings → Updates has
a manual **Check Now** action, and automatic checks can be turned off there.
Draft and prerelease releases are ignored.

Before anything is staged, Pulse verifies the download over HTTPS, checks the
redirect hosts, compares SHA-256 against the release `.sha256` asset and the
GitHub asset digest, requires exactly one `Pulse.app` in the archive, checks
the bundle identifier and embedded version, and verifies the Apple code
signature (TeamIdentifier `9Y4B7WBUU2`, Apple Development authority). Any
mismatch discards the download and leaves the installed app untouched.

A verified update installs itself only when no task draft is open and the
popover is closed; otherwise a "Pulse 0.1.x is ready" banner with **Restart**
and **Later** appears above the task list, and quitting applies it. Task data,
existing preferences and Keychain items are not touched. The current app is
backed up to `~/Library/Application Support/Pulse/Backups/` and restored if
replacement fails; progress is logged to
`~/Library/Logs/Pulse/update.log`.

Updates work only when Pulse runs from a user-writable `/Applications/Pulse.app`;
development builds report that updates are disabled. Updates are enabled from
0.1.3 onward, so replacing 0.1.2 is a manual DMG install. The preview remains
Apple Development signed, not Developer ID signed or notarized. See
[the auto-update contract](docs/auto-update.md) for the verification chain and
failure behavior.

## Build and run

Requirements: macOS 13 or newer and Xcode 26.6 or a compatible Xcode version.

1. Open `Pulse.xcodeproj` in Xcode.
2. Select the `Pulse` scheme and **My Mac**, then Run.
3. Sign in to Codex if needed, then click the Codex icon in the menu bar. The Home popover shows Tasks first; click its compact Codex status for quota details, or the gear for Settings. Both pages return to Home. Click the menu bar item again or click outside to dismiss the popover. Pointer departure from both it and the menu bar item starts a 180 ms grace interval; returning cancels the close. Opening and dismissal use native macOS animation, with a short 300 ms opening guard that also waits for presentation to finish. System **Reduce Motion** disables animation. Choose **Quit Pulse** in Settings to exit. Pulse has no Dock icon.

Command-line build:

```sh
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/PulseDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/PulseDerivedData CODE_SIGNING_ALLOWED=NO test
```

After rebuilding, quit any running Pulse instance and launch the new build. A menu bar app can keep displaying the previous icon and readout until its process restarts.

`project.yml` is the [XcodeGen](https://github.com/yonaskolb/XcodeGen) source for the checked-in Xcode project. XcodeGen is only needed if you change project structure: run `xcodegen generate` and commit the updated `.xcodeproj` together with `project.yml`. The app has `App`, `Core`, `Features`, and `UI` source directories. Unit tests use synthetic usage responses, a mock usage provider, and a simulated login item service. The test scheme disables live provider refresh in its app host, so tests do not query a real account.

## Publishing a release

Releases are cut with one command:

```sh
./scripts/release.sh <version>
```

Run it from a clean `main` checkout with an authenticated `gh` account and the
local Apple Development signing identity available; `--dry-run` runs the
preflight checks without changing anything.

The script runs the tests, bumps `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` in `project.yml`, regenerates `Pulse.xcodeproj` with
XcodeGen, builds a universal Release app, signs it with the local Apple
Development identity, packages and verifies the DMG and ZIP, then installs the
verified build locally. Finally it commits, tags, pushes and creates the GitHub
release with four assets: `Pulse-<version>.dmg` and
`Pulse-<version>.dmg.sha256` for manual installs, and `Pulse-<version>.zip`
plus `Pulse-<version>.zip.sha256` for the in-app updater.

The verified build is installed before anything is pushed or tagged, so the
locally installed app and the published assets are the same signed build. The
DMG and ZIP contain that one app; the updater consumes the ZIP and rejects a
bundle whose identifier, version or signature does not match. Release notes
live in `docs/releases/<version>.md`.

## Current settings

**Launch at login** requests registration through macOS Login Items. Pulse shows the actual system status separately from the saved preference; macOS may require approval in System Settings or reject registration from a development build. **Show Pulse name in menu bar** adds “Pulse” before the Codex readout. Both preferences start off and are stored in UserDefaults. Automated tests never modify the machine's Login Items.

## Codex usage

Pulse launches the local Codex app-server and requests its ChatGPT rate-limit state. With one reported window, the menu bar and Home summary show only the remaining percentage, such as `98%`; with multiple windows, they use short labels, such as `5h 66% 7d 63%`. Loading, unavailable data, and errors never become a fabricated percentage. The separate Usage page gives window, reset, update, and refresh details. Pulse refreshes at startup and while running. It reads no Codex authentication files and stores no usage credentials.

If the app cannot find Codex, install or launch Codex and check that its CLI works in a terminal. Development builds can also use the `CODEX_BIN` environment variable to point to the executable. A failed explicit override is reported as an error. The local CLI protocol and app bundle layout can change, so please report reproducible failures without sharing account secrets.

## 88VIP balance

Open **Settings → Providers**, enter your 88VIP API key, and select **Save key**. Pulse stores the key only in your macOS Keychain. It queries 88API's documented billing subscription and usage endpoints, calculates the remaining balance in USD, and shows it beside Codex in the popover. The full Usage page includes the limit, used amount, remaining amount, available expiry, update time, and a manual refresh action.

88VIP refreshes at launch and every ten minutes. Opening the popover refreshes a reading older than 60 seconds; selecting the compact status or the Usage page's refresh control requests it immediately. Network requests time out instead of leaving refresh controls busy indefinitely. Missing keys and other unavailable/error states show an error marker in the compact status, with the detailed reason on the Usage page. Partial responses are retried on a later popover open after a 60-second cooldown. Pulse never converts a USD value to another currency or fabricates a remaining balance. Clicking the Codex status likewise requests a fresh reading.

## DeepSeek balance

Open **Settings → Providers**, enter your DeepSeek API key, and select **Save key**.
Pulse stores it only in macOS Keychain, independently of 88VIP. **Replace key**
and **Remove key** immediately clear the previous reading and refresh the account.
The integration uses the [official account balance endpoint](https://api-docs.deepseek.com/api/get-user-balance);
it monitors API account balance rather than a chat subscription or token history.

The Home status shows the reported total with `¥` for CNY or `$` for USD. When
both are reported, Home prefers CNY and Usage lists the totals separately with
explicit currency labels. Pulse neither converts nor sums currencies. Zero and
negative reported totals remain valid readings. Click the DeepSeek whale status
for Usage details, update time, setup/error guidance, and manual refresh.

DeepSeek refreshes at launch and every ten minutes, on popover open when the
reading is older than 60 seconds, and immediately after a key change or manual
refresh. Requests time out after 20 seconds. Missing keys and failed requests
show `!` in Home and explain the reason in Usage; an old amount is never kept as
the current result after a failure. Provider controls sit toward the leading
edge and wrap as complete controls when amounts or quota windows need space.
Only a readout wider than the entire row scrolls horizontally; ordinary amounts
and their decimal digits remain visible in full within the 360 × 510 popover.

## Built-in tasks

Pulse has independent native to-do lists. **Todo** always holds tasks without a
custom tag; each custom tag is another list, and each task belongs to one list.
Use the tab bar's **+** to create an empty tag. Drag any tab to set the order,
or use **Move Left** / **Move Right** from its context menu and from Settings →
Tasks; the order is saved and survives relaunch. A separate centered **+** at
the end of the task list expands quick entry; Enter saves and collapses it
again.
Collapse without saving to retain a draft for later. Options expose single-list
selection, **New tag…** and **Repeat daily**. The compact editor has explicit
Cancel/Save actions and list/repeat settings. Moving a task changes its list.
Completed tasks remain in a counted, collapsible section.

Delete a task directly and use **Undo** to restore it. The last 20 deletions stay
available until Pulse quits. Removing a tag requires confirmation and moves its
tasks to Todo. Quick-entry drafts survive list/page switches and popover closure.
Legacy data is normalized with an original-file backup, so previously hidden
untagged tasks become reachable in Todo. Data stays local in schema-version-1
JSON. See [the task interaction and storage contract](docs/builtin-tasks.md)
for failure behavior, compatibility and manual acceptance.

## Direction

- **AI status:** Codex, 88VIP, and DeepSeek are connected. Provider-specific capabilities for OpenAI API, GLM, OpenRouter, and custom endpoints are planned. A balance and a rate-limit window are displayed as different kinds of information.
- **Local to-dos:** the native list is Pulse's single task system — tag tabs you can drag into your own order, centered quick add, completed rows kept visible, and per-task daily repeat. Everything is stored locally in one JSON file on this Mac.
- **Privacy:** the app runs locally. 88VIP and DeepSeek API keys are stored in macOS Keychain; ordinary preferences use UserDefaults. Tasks are stored locally; Pulse keeps no imported note content and has no analytics.

See [UI layout and interaction](docs/ui-layout-refactor.md), [Codex integration](docs/phase2-codex-provider.md), [Phase 1 foundation](docs/phase1-foundation.md), [menu bar status requirements](docs/08-menu-bar-status-requirements.md), [the roadmap](docs/06-mvp-roadmap.md), [architecture decisions](docs/02-architecture-decisions.md), and [reference analysis](docs/01-reference-analysis.md). Contributions and issue reports are welcome. Please do not post API keys or private notes in issues.

## 中文简介

Pulse 计划成为一个本地优先的 macOS 菜单栏工作入口，集中查看 AI 服务额度和本地待办。目前已接入本机 Codex CLI、可选的 88VIP USD 余额与 DeepSeek 原币种余额：菜单栏只显示 Codex，弹窗头部并排显示三项紧凑状态，点击可进入 Usage 详情，设置是同一弹窗中的另一页。任务区只有一套原生待办：标签即标签页，没有"全部"和"未分类"标签页，没有标签时显示单个指引标签 "Todo"，空状态为"暂无任务"或"此标签下暂无任务"；选中标签为填充的圆角胶囊样式，键盘焦点是与形状匹配的柔和描边而不是方框。标签页可直接拖拽调序（拖动时会有插入位置提示），也可用右键菜单的 Move Left / Move Right（⌥⌘← / ⌥⌘→）或设置页调整，顺序保存在本地并重启后保持；"Todo" 始终在最左且不可拖动。列表下方居中的 `+` 就地展开内联新建（文本、标签菜单、新建标签、"每日重复"复选框、Add/Cancel），标签行右端的 `+` 可按标签新建任务或新建标签。已完成任务不会消失：它们变暗并加删除线，排在未完成任务之后的 "Completed" 分组下，悬停行可删除（需确认），也可在编辑页删除（同样需确认）。勾选"每日重复"的任务会记录本地日历日；每次打开 Pulse（弹窗打开或任务界面出现）都会把前一天已完成的重复任务恢复为未完成，任务正文旁有循环箭头小标记。任务保存在本地 `~/Library/Application Support/Pulse/tasks.json`，模式版本仍为 1，新增键为可选，旧版本文件无需迁移即可读写。设置中的 Tasks 页只管理标签（排序/重命名/删除），没有任务来源选项，旧的连接与导入数据保持原样。更多 Provider 尚未实现。后续阶段见 [路线图](docs/06-mvp-roadmap.md)。

## License

MIT. See [LICENSE](LICENSE). The menu bar icon is copied from `codex-usage-status` under MIT; see [third-party notices](THIRD_PARTY_NOTICES.md) for attribution and license terms. No reference application source code is copied into Pulse.
