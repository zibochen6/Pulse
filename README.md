# Pulse

Pulse is an early-stage, local-first macOS menu bar assistant for people who use AI services every day. The intended product brings AI usage status and daily to-dos into one quick daily entry point.

**Pulse 0.1.28** places Quick Copy in the Home toolbar and removes the task search bar.

The menu bar remains Codex-only. Select a provider to inspect its own usage, or connect an optional service from its status card. Tasks support independent tag lists, quick entry, daily repeat and deletion undo. Everything stays local; API keys are stored in macOS Keychain. See [UI and interaction](docs/ui-layout-refactor.md) and [motion](docs/popover-motion.md) for the current behavior.

[View the earlier interface and 18-second demo](docs/media/ui-redesign/README.md) in English or Simplified Chinese. All preview values and tasks are clearly labelled sample data.

## Download and install

Download [Pulse 0.1.28](https://github.com/zibochen6/Pulse/releases/tag/v0.1.28)
for macOS 13 or newer (Apple Silicon and Intel). Open the DMG and drag Pulse
to Applications. Quit the previous Pulse instance before replacing it, then
launch `/Applications/Pulse.app`; its settings and task storage are retained.
The release publishes `Pulse-0.1.28.dmg` with a SHA-256 checksum for manual
installs, plus `Pulse-0.1.28.zip` and its checksum for the in-app updater; the
DMG and ZIP contain the same signed app.

This preview is signed with an Apple Development certificate, **not Developer ID
signed or notarized**. macOS may block first launch. If you trust the downloaded
build, use the available **Open Anyway** option in System Settings → Privacy &
Security after attempting to launch; follow [Apple's guidance](https://support.apple.com/102445)
and do not disable Gatekeeper. Source builds
remain available below. See [0.1.28 release notes](docs/releases/0.1.28.md) for
changes and current limits.

## Automatic updates

Pulse 0.1.3 and later check the public GitHub latest-release feed about ten
seconds after launch and every six hours while running. Settings → Updates has
a manual **Check for updates** action, and automatic checks can be turned off there.
Draft and prerelease releases are ignored.

Before anything is staged, Pulse verifies the download over HTTPS, checks the
redirect hosts, compares SHA-256 against the release `.sha256` asset and the
GitHub asset digest, requires exactly one `Pulse.app` in the archive, checks
the bundle identifier and embedded version, and verifies the Apple code
signature (TeamIdentifier `9Y4B7WBUU2`, Apple Development authority). Any
mismatch discards the download and leaves the installed app untouched.

A verified update installs itself only when the popover and Settings are
closed, no unfinished task/settings draft remains and no local save is pending; otherwise a "Pulse 0.1.x is ready" banner with **Restart**
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

## Edit a recording

In **Settings → Recording edits**, choose a workspace that already contains the `talking-head-autoclip` project skill. The workflow uses its local Python environment at `~/.talking-head-autoclip/venv/bin/python`, FFmpeg, transcription model, and signed-in publishing profiles. These dependencies stay on your Mac. Set the model and reasoning effort here for future edits; the defaults are `gpt-6.2-sol` and `low`.

Click **Edit recording** to use the latest `rec_<digits>.MP4` or `IMG_<digits>.MOV` added to Downloads. Click again during a run to see its activity. Finished media and the review page are under the workspace’s `output/` folder. Douyin, Xiaohongshu, Kuaishou, and Bilibili each have a separate draft status. You decide when to publish. Click **Done** on the Home result when you finish. Right-click **Edit recording** and select **Last editing task** to revisit it.

## Build and run

Requirements: macOS 13 or newer and Xcode 26.6 or a compatible Xcode version.

1. Open `Pulse.xcodeproj` in Xcode.
2. Select the `Pulse` scheme and **My Mac**, then Run.
3. Sign in to Codex if needed, then click the Codex icon in the menu bar. The Home popover shows Tasks first; click its compact Codex status for quota details, or the gear for Settings. Usage returns to Home; Settings opens in its own window and is also available with **⌘,**. Click the menu bar item again or click outside to dismiss the popover. Pointer departure from both it and the menu bar item starts a 180 ms grace interval; returning cancels the close. Opening and dismissal use native macOS animation, with a short 300 ms opening guard that also waits for presentation to finish. System **Reduce Motion** disables panel and custom transitions and uses static busy indicators. Choose **Quit Pulse** in Settings to exit. Pulse has no Dock icon.

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

Open **Settings → AI services**, enter your 88VIP API key, and select **Save and verify**. Pulse stores the key only in your macOS Keychain. It queries 88API's documented billing subscription and usage endpoints, calculates the remaining balance in USD, and shows it beside Codex in the popover. The full Usage page includes the limit, used amount, remaining amount, available expiry, update time, and a manual refresh action.

88VIP refreshes at launch and every ten minutes. Opening the popover refreshes a reading older than 60 seconds; selecting a configured service's compact status or the Usage page's refresh control requests it immediately. Network requests time out instead of leaving refresh controls busy indefinitely. A missing key shows **Connect** and opens that service in Settings. Other unavailable/error states show an error marker, with the detailed reason on the Usage page. Partial responses are retried on a later popover open after a 60-second cooldown. Pulse never converts a USD value to another currency or fabricates a remaining balance. Clicking the Codex status likewise requests a fresh reading.

## DeepSeek balance

Open **Settings → AI services**, enter your DeepSeek API key, and select **Save and verify**.
Pulse stores it only in macOS Keychain, independently of 88VIP. **Manage connection**
reveals **Save and verify** for a replacement key and **Disconnect** for removal.
Changing or removing the key immediately invalidates the previous reading.
The integration uses the [official account balance endpoint](https://api-docs.deepseek.com/api/get-user-balance);
it monitors API account balance rather than a chat subscription or token history.

The Home status shows the reported total with `¥` for CNY or `$` for USD. When
both are reported, Home prefers CNY and Usage lists the totals separately with
explicit currency labels. Pulse neither converts nor sums currencies. Zero and
negative reported totals remain valid readings. Click the DeepSeek whale status
for Usage details, update time, setup/error guidance, and manual refresh.

DeepSeek refreshes at launch and every ten minutes, on popover open when the
reading is older than 60 seconds, and immediately after a key change or manual
refresh. Requests time out after 20 seconds. Missing keys show **Connect** and
open Settings; failed requests show `!` in Home and explain the reason in Usage.
An old amount is never kept as
the current result after a failure. Provider controls sit toward the leading
edge and wrap as complete controls when amounts or quota windows need space.
Only a readout wider than the entire row scrolls horizontally; ordinary amounts
and their decimal digits remain visible in full within the 400 × 520 popover,
which never grows as content changes.

## Built-in tasks

Pulse has independent native to-do lists. **Todo** always holds tasks without a
custom tag; each custom tag is another list, and each task belongs to one list.
Use the tab bar's **+** to create an empty tag. The selected tag's **…** menu exposes rename, move and removal; **All tags** opens searchable management without a tag-count cap. Drag any tab to set the order,
or use **Move left** / **Move right** from its context menu, or **Move up** /
**Move down** in Settings → Tasks; the order is saved and survives relaunch. A left-aligned **+ Add task**
row follows all task rows and expands quick entry; Enter saves and collapses it
again.
Collapse without saving to retain a draft for later. Options expose single-list
selection, **New tag…** and **Repeat daily**. The compact editor has explicit
Cancel/Save actions and list/repeat settings. Moving a task changes its list.
Completed tasks stay in place, dimmed and struck through.

Delete a task directly and use **Undo** to restore it. The last 20 task/list
deletions stay available until Pulse quits. Deleting a custom tag requires
confirmation and removes that list and all its tasks together. One Undo restores
the tag and tasks at their original relative positions. An affected unfinished
draft must first be saved or explicitly discarded; it is never silently lost.
Quick-entry drafts survive list/page switches and popover closure.
Legacy data is normalized with an original-file backup, so previously hidden
untagged tasks become reachable in Todo. Data stays local in schema-version-1
JSON. See [the task interaction and storage contract](docs/builtin-tasks.md)
for failure behavior, compatibility and manual acceptance.

## Obsidian Today Tasks

Install the compatible **Personal Dashboard** plugin (0.6.10 or later) in
Obsidian desktop and enable it for the vault you want to connect. In Pulse, open
**Settings → Tasks → Choose Vault** and select that vault's folder. Pulse shows
only **Today Tasks** while the vault is paired. Disconnect the vault to open your
existing Pulse lists and tag settings.

Both apps share the dashboard's Today Tasks, including project tasks scheduled
for today. Deleting a quick capture removes its Markdown checkbox. Removing a
project task from Today preserves the checkbox in its project note. While
Obsidian is closed, Pulse shows queued edits and sends them when the connected
vault opens again. Coordination is local to this Mac.

## Direction

- **AI status:** Codex, 88VIP, and DeepSeek are connected. Provider-specific capabilities for OpenAI API, GLM, OpenRouter, and custom endpoints are planned. A balance and a rate-limit window are displayed as different kinds of information.
- **Tasks:** Native lists support tags and daily repeat. The optional Obsidian connection brings the dashboard's Today Tasks into the same menu bar panel.
- **Quick Copy:** open the copy icon in the Home toolbar to save named prompts and commands. Click an entry's name to copy its full text to the clipboard.
- **Privacy:** the app runs locally. 88VIP and DeepSeek API keys are stored in macOS Keychain. Native tasks, the paired vault preference and its sync state stay on this Mac. Pulse has no analytics.

See [UI layout and interaction](docs/ui-layout-refactor.md), [Codex integration](docs/phase2-codex-provider.md), [Phase 1 foundation](docs/phase1-foundation.md), [menu bar status requirements](docs/08-menu-bar-status-requirements.md), [the roadmap](docs/06-mvp-roadmap.md), [architecture decisions](docs/02-architecture-decisions.md), and [reference analysis](docs/01-reference-analysis.md). Contributions and issue reports are welcome. Please do not post API keys or private notes in issues.

## 中文简介

Pulse 是本地优先的 macOS 菜单栏工具，将 AI 服务状态和每日待办放在一起。0.1.28 将「快速复制」移到首页顶部，并移除待办搜索栏。可从上方链接下载新版本。

- **AI 状态**：Codex 额度、88VIP USD 余额和 DeepSeek 原币种余额。点击哪个服务，就查看哪个服务；未配置、验证中、连接成功和失败分别表达，保存密钥不冒充连接成功。
- **标签即列表**：Todo 固定保留，自定义标签可通过可见的省略号菜单编辑、删除和排序；全部标签入口支持搜索，没有人为数量上限。删除标签会一并删除列表任务，一次撤销可恢复整组；最多保留当前运行内最近 20 次删除，并保护未提交草稿。
- **日常操作**：列表下方添加任务，支持每日重复；完成任务原地显示，删除任务可以撤销。跨标签、页面和窗口保留草稿；中文输入法确认候选词不会误提交。
- **快速复制**：从首页打开「快速复制」，给常用提示词或指令命名。点击名称即可复制全文，条目上会短暂显示「已复制」。
- **设置与动画**：使用齿轮或 ⌘, 打开独立设置。保留鼠标移出 180 毫秒后关闭面板的习惯，输入、菜单和拖拽期间暂停；跟随系统减少动态效果。
- **今日待办同步**：在 Pulse 的「设置 → 待办」选择已安装兼容看板插件的知识库。两端可新增、勾选、撤销完成和删除，Obsidian 关闭时操作会在本机排队。断开知识库后可访问原有本地清单。
- **本地数据**：原有任务文件保持 schema 1，密钥保存在 macOS Keychain，待办同步通过本机文件完成。

更多细节见 [界面与交互](docs/ui-layout-refactor.md)、[本地任务](docs/builtin-tasks.md) 和 [推广展示](docs/07-community-launch-plan.md)。

## License

MIT. See [LICENSE](LICENSE). The menu bar icon is copied from `codex-usage-status` under MIT; see [third-party notices](THIRD_PARTY_NOTICES.md) for attribution and license terms. No reference application source code is copied into Pulse.
