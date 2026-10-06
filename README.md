# Pulse

Pulse is an early-stage, local-first macOS menu bar assistant for people who use AI services and Obsidian every day. The intended product brings AI usage status and Markdown tasks into one quick daily entry point.

**Current state:** Pulse is a buildable menu bar app with Codex usage, optional 88VIP balance integrations, built-in tasks with multiple tags, and optional Apex Dashboard tasks with creation and checkbox completion saved to Markdown. It reads rate-limit windows from a locally installed, signed-in Codex CLI and can query a user-configured 88VIP account balance. The menu bar remains Codex-only; the popover header shows both compact statuses. Click either status for Usage details; Settings is another page in the same popover. This repository is not a downloadable MVP release yet.

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

`project.yml` is the [XcodeGen](https://github.com/yonaskolb/XcodeGen) source for the checked-in Xcode project. XcodeGen is only needed if you change project structure: run `xcodegen generate` and commit the updated `.xcodeproj` together with `project.yml`. The app has `App`, `Core`, `Features`, and `UI` source directories. Unit tests use synthetic usage responses, a mock usage provider, and a simulated login item service. The test scheme disables live Codex refresh in its app host, so tests do not query a real account.

## Current settings

**Launch at login** requests registration through macOS Login Items. Pulse shows the actual system status separately from the saved preference; macOS may require approval in System Settings or reject registration from a development build. **Show Pulse name in menu bar** adds “Pulse” before the Codex readout. Both preferences start off and are stored in UserDefaults. Automated tests never modify the machine's Login Items.

## Codex usage

Pulse launches the local Codex app-server and requests its ChatGPT rate-limit state. With one reported window, the menu bar and Home summary show only the remaining percentage, such as `98%`; with multiple windows, they use short labels, such as `5h 66% 7d 63%`. Loading, unavailable data, and errors never become a fabricated percentage. The separate Usage page gives window, reset, update, and refresh details. Pulse refreshes at startup and while running. It reads no Codex authentication files and stores no usage credentials.

If the app cannot find Codex, install or launch Codex and check that its CLI works in a terminal. Development builds can also use the `CODEX_BIN` environment variable to point to the executable. A failed explicit override is reported as an error. The local CLI protocol and app bundle layout can change, so please report reproducible failures without sharing account secrets.

## 88VIP balance

Open **Settings → Providers**, enter your 88VIP API key, and select **Save key**. Pulse stores the key only in your macOS Keychain. It queries 88API's documented billing subscription and usage endpoints, calculates the remaining balance in USD, and shows it beside Codex in the popover. The full Usage page includes the limit, used amount, remaining amount, available expiry, update time, and a manual refresh action.

88VIP refreshes at launch and every ten minutes. Opening the popover refreshes a reading older than 60 seconds; selecting the compact status or the Usage page's refresh control requests it immediately. Network requests time out instead of leaving refresh controls busy indefinitely. Missing keys and other unavailable/error states show an error marker in the compact status, with the detailed reason on the Usage page. Partial responses are retried on a later popover open after a 60-second cooldown. Pulse never converts a USD value to another currency or fabricates a remaining balance. Clicking the Codex status likewise requests a fresh reading.

## Built-in tasks

New users start with built-in tasks: no Obsidian setup is required. Use **Add Task**
at the bottom of Home to expand an inline input under the list. Enter text,
select multiple tags or create tags, and Save; the task list stays visible.
Click a checkbox to complete or undo completion; click task text to edit it.
Completed tasks stay in place. Deleting a task requires confirmation.

The compact filter row provides **All**, **Untagged**, and each named tag. Rename
or remove tags through **Settings → Tasks**; deleting a tag never deletes its tasks.
Tasks are saved locally in `~/Library/Application Support/Pulse/tasks.json` and
restored after restart. Persistence errors appear inline; failed saves retain the
draft. Editing pauses pointer-departure close; outside clicks still dismiss, and
unsaved task input is retained when reopening during the same app session.

**Settings → Tasks → Task source** switches between Built-in tasks and Obsidian
Dashboard. The sources remain independent; switching never merges, converts or
deletes data. Existing users with a saved Dashboard keep it selected on upgrade. If Obsidian
is not connected, its task page also offers **Use built-in tasks** directly.
See [built-in task storage and acceptance](docs/builtin-tasks.md).

## Apex Dashboard tasks

Open **Settings → Tasks**, choose **Obsidian Dashboard**, and select one Apex Dashboard Markdown file. Pulse
reads the verified Apex structure—frontmatter columns, `##` columns, `###`
cards, and Markdown checkbox rows—and shows it in the Home task area.
The file chooser opens as a separate window after the popover finishes closing.
Selecting or cancelling returns to Tasks settings; cancelling keeps the previous
file. Use **Choose another file** to reconnect a moved Dashboard. Settings shows
the actual load/parse result, with a retryable explanation if connection fails.
If the popover cannot close for the chooser, Pulse releases the waiting state
and offers retry instead of leaving the button disabled. Reconnecting discards
the old file's unsaved Apex draft, including when the new file cannot be parsed;
ordinary refreshes and navigation retain the draft.
Selecting a file while using built-in tasks does not switch sources; choose
**Obsidian Dashboard** under **Task source** to show its tasks on Home.
Use column tabs to browse. **Add task** expands the input directly beneath the
list. Enter text, choose an existing column and group, optionally select or add
ordinary `#tags`, then save directly to the Dashboard. No creation page is opened.
No local copy is created. A failed save keeps the draft for retry; opening and
closing the popover keeps unsaved input during the same app session. A column
without groups needs a group created in Obsidian first, or choose another column.
After saving, Pulse returns to the chosen column. **Click the checkbox to complete or undo completion;
click task text to open the source file in Obsidian.** Completion is confirmed
after saving and rereading the original Markdown; it stays in the same position.

For completion, only the selected checkbox state character is changed. UTF-8 BOM, LF/CRLF,
metadata, indentation and the rest of the file are retained. Nested checkboxes
use four-space/tab indentation; special task states remain read-only. Ambiguous
external edits produce an inline error instead of a guessed update. Saving is
local, asynchronous, and serialized; duplicate clicks on a pending task are
ignored. New tasks are inserted into the selected group while retaining every
existing byte, and receive a hidden Obsidian block identifier for safe retries.
Insertion uses a coordinated atomic replacement, which also requires permission
to create a temporary file in the Dashboard's directory. File permissions still
apply; choose the file again if access is lost.

Pulse rereads the file on popover open, after saves, and through
**Settings → Tasks → Refresh**. It does not scan a Vault, watch files, infer due
dates, reorder tasks, or cascade completion to children. File coordination
cannot fully prevent noncooperating external editors from racing with a save.
See [task write-back and manual acceptance](docs/apex-task-writeback.md); the
[read-only MVP document](docs/apex-dashboard-readonly-mvp.md) records the earlier
foundation.
See [Dashboard task creation and settings feedback](docs/apex-task-creation.md)
for the current insertion safety and manual acceptance steps. Settings actions
have visible primary, secondary and removal styles with short hover/press
feedback; Reduce Motion disables these transitions.

## Direction

- **AI status:** Codex and 88VIP are connected. Provider-specific capabilities for OpenAI API, DeepSeek, GLM, OpenRouter, and custom endpoints are planned. A balance and a rate-limit window are displayed as different kinds of information.
- **Obsidian tasks:** Pulse can read one selected Apex Dashboard in the verified
  format. Checkbox completion writes back to the selected Markdown; general Vault scanning and other task editing remain future work.
- **Privacy:** the app runs locally. 88VIP API keys are stored in macOS Keychain; ordinary preferences use UserDefaults. Built-in tasks are stored locally; Pulse stores no imported Vault content and has no analytics.

See [UI layout and interaction](docs/ui-layout-refactor.md), [Codex integration](docs/phase2-codex-provider.md), [Phase 1 foundation](docs/phase1-foundation.md), [menu bar status requirements](docs/08-menu-bar-status-requirements.md), [the roadmap](docs/06-mvp-roadmap.md), [architecture decisions](docs/02-architecture-decisions.md), and [reference analysis](docs/01-reference-analysis.md). Contributions and issue reports are welcome. Please do not post API keys or private notes in issues.

## 中文简介

Pulse 计划成为一个本地优先的 macOS 菜单栏工作入口，集中查看 AI 服务额度和 Obsidian Markdown 待办。目前已接入本机 Codex CLI、可选的 88VIP USD 余额，以及 Apex Dashboard 任务展示和完成状态写回：菜单栏只显示 Codex；在弹窗点击复选框可完成／取消任务并保存到原 Markdown，点击正文打开 Obsidian。内置待办支持增删改、完成状态与多个标签，新用户无需 Obsidian 即可使用；两种任务来源在设置中切换，数据保持独立。通用 Vault 扫描和更多 Provider 尚未实现。后续阶段见 [路线图](docs/06-mvp-roadmap.md)。

## License

MIT. See [LICENSE](LICENSE). The menu bar icon is copied from `codex-usage-status` under MIT; see [third-party notices](THIRD_PARTY_NOTICES.md) for attribution and license terms. No reference application source code is copied into Pulse.
