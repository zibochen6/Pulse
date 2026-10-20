# State Management

## Scenario: menu bar preferences and macOS Login Items

### 1. Scope / Trigger

Phase 1's AppKit status item and SwiftUI settings share one `@MainActor AppConfig: ObservableObject`. Use this pattern for ordinary local preferences that affect both layers. It does not define future provider or task state.

### 2. Signatures

```swift
@MainActor protocol LoginItemManaging {
  var status: LoginItemStatus { get }
  func setEnabled(_ enabled: Bool) throws
}

@MainActor final class AppConfig: ObservableObject {
  init(defaults: UserDefaults, loginItemService: any LoginItemManaging)
  func setShowMenuBarLabel(_ enabled: Bool)
  func setLaunchAtLogin(_ enabled: Bool)
  func refreshLoginItemStatus()
}
```

The production initializer supplies `.standard` and `SystemLoginItemService()` by default. The app delegate owns one `AppConfig` and passes it to `HomeView`.

### 3. Contracts

- UserDefaults keys `launchAtLoginRequested` and `showMenuBarLabel` store Booleans; absent keys mean `false`.
- `launchAtLoginRequested` is user intent. `loginItemStatus` is the operating system's observed state and can independently be `notRegistered`, `enabled`, `requiresApproval`, or `notFound`.
- Opening the popover calls `refreshLoginItemStatus()` before presentation. Enabling or disabling calls `SMAppService.mainApp` through `LoginItemManaging`, then refreshes status.
- The status item renders the bundled Codex icon plus the current `UsageRefreshState` title (`…`, percentage, `--`, or `!`). `showMenuBarLabel` only adds the word “Pulse”; it never hides the usage state.
- `CodexMenuIcon.png` is the monochrome template artwork for the macOS status bar only. Popover views use `CodexProviderIcon`, backed by the alpha-enabled `CodexColorIcon.png`, so the Codex mark keeps its supplied blue-violet color in both Aqua and Dark Aqua. Do not set the popover image to template rendering or reuse it for the status item.
- `DeepSeekProviderIcon` must preserve the actual DeepSeek whale geometry, including the belly, eye and tail negative spaces. The initial generic whale silhouette was rejected by the user. Reuse the shared native vector component on Home, Usage and Settings; preserve aspect ratio inside its existing frame and use the reference blue `#4D6BFE`. Obtain original vector geometry from the official source rather than approximating the mark. Keep attribution in `THIRD_PARTY_NOTICES.md` and inspect an enlarged render as well as the 14–18-point icons in both appearances.
- The popover uses one `HomeView.popoverSize` for both AppKit and SwiftUI and covers the entire hosting surface with adaptive opaque `windowBackgroundColor`. Section cards use opaque `controlBackgroundColor`. Native show/close animation is enabled unless NSWorkspace reports Reduce Motion; never restore the former clear background or unconditionally disable motion. Observe accessibility display changes and reread the setting before opening/closing. Animation duration and appearance are owned by macOS.
- `@Published` emits during `willSet`. Subscribers that update AppKit controls must use the emitted value rather than re-read the stored property in the same callback.
- Rebuilding the app does not replace an already-running menu bar process. Restart the built app before judging its icon, quota, or popover appearance.

### 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| No saved preference | Show both settings off. |
| macOS already reports `enabled` and user requests on | Do not call register again; show enabled. |
| macOS reports `notRegistered` and user requests off | Do not call unregister again; show not enabled. |
| macOS reports `requiresApproval` | Keep requested intent, show approval guidance, do not claim enabled. |
| Registration throws | Keep menu bar and popover usable; expose `loginItemError` and refresh actual status. |
| Later refresh matches requested state | Clear an obsolete login item error. |

### 5. Good / Base / Bad Cases

- Good: user enables login launch, macOS reports `enabled`, and Settings reports success.
- Base: no usage source or login preference exists; menu bar shows `--%` and Settings reports not enabled.
- Bad: registration fails or needs approval; the requested toggle may be on, while a separate message reports that the OS has not enabled it.

### 6. Tests Required

Use an isolated `UserDefaults(suiteName:)` and a fake `LoginItemManaging`; unit tests must never register the test host as a real login item. Assert preference persistence, registration and unregistration requests, approval state, failure state, idempotent already-enabled behavior, and stale-error clearing. Build with Swift 6 and macOS 13 deployment settings.

### 7. Wrong vs Correct

```swift
// Wrong: @Published may still expose the old stored value inside sink.
config.$showMenuBarLabel.sink { [weak self] _ in
  self?.updateStatusButton(showName: config.showMenuBarLabel)
}

// Correct: use the value emitted for this update.
config.$showMenuBarLabel.sink { [weak self] showName in
  self?.updateStatusButton(showName: showName)
}
```

## Phase 2A addition: shared usage state

`PulseAppDelegate` owns one `UsageController` and passes it to `HomeView`. The controller is `@MainActor` and publishes loading, success, unavailable, and failure. `UsageView` and the AppKit status item consume that same state. When subscribing to `usage.$state`, use the emitted value because `@Published` emits during `willSet`. The normal refresh period is 60 seconds; manual refresh does not overlap an active fetch. On failure, the status item shows `!` and the popover shows the message instead of presenting the previous percentage as current. See [Codex Usage](../backend/codex-usage.md) for the app-server contract and tests.

## Scenario: in-popover navigation and guarded pointer dismissal

### 1. Scope / Trigger

Home, Usage detail, and Settings share one transient popover. Pointer departure from both the menu bar button and popover content schedules a delayed close; an outside click still uses AppKit's native transient close.

### 2. Signatures

```swift
@MainActor final class PopoverHoverController {
  func beginOpening()
  func presentationDidShow()
  func synchronize(statusButton: Bool, content: Bool, popoverWindow: Bool)
  func entered(_ region: PopoverPointerRegion)
  func exited(_ region: PopoverPointerRegion)
  func requestClose()
  func beginClosing()
  func reset()
}

enum PopoverPage: Equatable {
  case home
  case usage
  case settings(SettingsDestination)
}

@MainActor final class PopoverPageController: ObservableObject {
  private(set) var page: PopoverPage { get }
  func showUsage()
  func showSettings(_ destination: SettingsDestination)
  func showHome()
  func reset()
}
```

`PulseAppDelegate` owns one `PopoverPageController` alongside the AppKit status item, popover, shared config, and shared usage controller. It passes the page controller to `HomeView` and calls `reset()` before opening and after any popover close. There is no navigation stack.

### 3. Contracts

- The Home header contains Pulse identity, the Settings gear, and independent compact Codex, 88VIP, and DeepSeek controls. Codex uses the real icon and `UsageMenuFormatter.title(for:)`: one window yields a bare percentage, multiple windows yield short labeled values, and loading/unavailable/failure yield `…`/`--`/`!`. Money remains a native-currency balance, separate from quota percentages. Home has no reset time, update time, or refresh control; those belong to Usage. The AppKit menu bar continues to use only Codex state.
- Header status controls begin beside the brand with flexible space after them, shifting them toward the leading edge. When they do not fit, place them in leading-aligned rows below the brand; wrap whole controls instead of clipping monetary decimals or overlapping Settings. Bound a single exceptionally wide quota control and make its text horizontally reachable. Use actual measured widths at the fixed 360 × 510 popover size. Keep the existing native colors, fonts, and task-region ownership.
- Clicking a provider control requests that provider's refresh, calls `showUsage()`, and displays full `UsageView` in a separate scrollable page. Manual refresh remains in Usage. Add Provider routes to Settings → Providers, which owns separate 88VIP and DeepSeek Keychain forms. Back from Usage or Settings calls `showHome()`.
- Tasks is Home's main region and has exactly one implementation: the native local list in `Pulse/Features/Tasks/Local/`. There is no source-switching configuration, no source picker, and no second surface; no UserDefaults preference decides where tasks come from. The tab row shows only saved tags in creation order (no `All`, no `Untagged` tab; zero tags render one `Todo` guidance tab), the centered `+` under the list expands the inline composer, completed rows stay visible dimmed and struck through under a `Completed` heading, and repeating tasks re-arm on popover open. Neither empty states nor loading states display fabricated sample tasks.
- `PopoverPageController` is presentation state only. It does not start an integration or change a UserDefaults key. `popoverDidClose` resets it to Home so a later open is task-first.
- `NSTrackingArea` on both the status button and hosting view uses mouse entry/exit, active-always, and visible-rect tracking. `PulseAppDelegate` calls `beginOpening()` before `show`, then seeds tracked regions from actual geometry. Opening requires both a minimum 300 ms click guard and `popoverDidShow`; events record presence but cannot request hover close until both complete. Reread actual button, content and whole-window geometry at that boundary. While shown, reconcile all three regions every 50 ms, including the arrow, so missed exits cannot latch hover forever.
- The controller has Closed, Opening, Interactive, PendingClose and Closing states. PendingClose waits 180 ms and rechecks actual pointer geometry before closure. Schedule only when no pending task exists: duplicate exits or reconciliation cannot extend the deadline. Returning to the button, content or arrow immediately cancels it; geometry alone can repair missed entry events.
- `requestClose` enters Closing and cancels timers before requesting native dismissal. `popoverWillClose` also enters Closing for native outside clicks. During Closing, tracking, stale presentation signals, duplicate close requests and status-item toggles cannot reopen or restart timers. Only `popoverDidClose` resets the controller and page state. A second click and outside click request dismissal immediately, without the hover grace interval. The hover controller never shows the popover.
- The popover retains its opaque adaptive background and fixed `HomeView.popoverSize` across page changes.
- Home keeps the task region visually dominant within the fixed popover size. The Usage detail page scrolls for extra quota windows and long messages; no detailed Usage content appears on Home.

### 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Pointer moves from status item toward popover | Grace period allows entry; entry cancels the close. |
| Pointer stays on the clicked status item through Opening | Geometry resampling retains the panel, including after two seconds. |
| Pointer leaves both and stays outside | Request native animated close after 180 ms, provided current geometry still confirms outside. |
| Pointer re-enters before deadline | Cancel close. |
| Pointer stays over the popover arrow without a content entry event | Reconcile window geometry; keep open until a later departure. |
| Guard expires but native presentation has not completed | Remain in Opening until `popoverDidShow`. |
| Repeated exit while PendingClose | Keep the original deadline. |
| Pointer/click returns during Closing | Finish dismissal; do not reverse or reopen the native animation. |
| AppKit closes from outside click or status item toggle | Reset pending close and pointer state. |
| Settings or placeholder entry is clicked inside popover | Navigate in place; do not request a close or integration. |
| Provider status is clicked | Refresh only that provider and show its real quota/balance, update time, and error state on Usage. |
| Popover closes while Usage or Settings is visible | Reset page state; next open shows Home and Tasks. |
| Codex returns one weekly window or multiple windows | Home shows bare percentage or labeled short values respectively, with no window-selection setting. |
| Codex refresh fails | Preserve the existing explicit error state, not a fabricated percentage. |
| Three provider controls do not fit beside the brand | Move them to leading-aligned rows below it; keep amounts and Settings hit area complete. |
| One quota label exceeds the full usable row | Bound that control's horizontal scroll area; sibling controls remain inside the popover. |
| DeepSeek returns CNY and USD | Prefer CNY in Home and show separate labelled currency rows in Usage. |
| Saved API key changes during a refresh | Clear the old reading and prevent the old request from publishing its result. |

### 5. Good / Base / Bad Cases

- Good: the user opens Pulse and sees a compact Codex status above the task list region, then clicks status to inspect full Usage detail.
- Base: the user views Settings or Usage, closes the popover, and sees Home on the next open.
- Bad: Codex refresh fails; Home shows `!`, while Usage detail explains the failure rather than repeating a stale percentage.

### 6. Tests Required

Unit tests cover the minimum guard plus native presentation completion, geometry resampling, short departure delay, duplicate exits, re-entry cancellation, missed events, arrow presence, Closing request gating and reset, and edit suspension. Check native NSPopover callbacks with animation enabled/disabled. Page tests assert Home → Usage, Home → Settings destination, Back → Home, and reset after completed closure. Render Home, Usage, and Settings in Aqua and Dark Aqua and assert opaque edges; keep existing usage/preference/task regressions. `DeepSeekRenderingTests` resolves actual `ProviderHeaderBoundsKey` anchors at 360 points: assert complete control IDs, leading insets, non-overlapping frames, amount text widths, whole-control wrapping, bounded oversized quota, and the single-row small-value case. Inspect representative images as well. Actual mouse delivery and animation appearance still require desktop checks; do not infer visual acceptance from these tests.

### 7. Wrong vs Correct

```swift
// Wrong: closes during the short trip from the menu bar button to the popover.
func mouseExited(with event: NSEvent) { popover.performClose(nil) }

// Correct: record the exit and let the shared controller close only after
// both tracked regions remain empty for the grace interval.
func mouseExited(with event: NSEvent) { hoverController.exited(.statusButton) }

// Wrong: leave Usage selected when AppKit dismisses the transient popover.
func popoverDidClose(_ notification: Notification) { hoverController.reset() }

// Correct: stop hover work before animating out, then reset pages after close.
func popoverWillClose(_ notification: Notification) {
  hoverController.beginClosing()
}

func popoverDidClose(_ notification: Notification) {
  hoverController.reset()
  pages.reset()
}
```

## Built-in tasks

The app delegate owns one `LocalTaskController`. The native local list in
`Pulse/Features/Tasks/Local/` is the only task system: there is no
source-switching configuration, no source picker, no second surface, and no
UserDefaults preference that decides where tasks come from. Unit host
initialization uses isolated defaults and a temporary task store.

Local list rows use sibling completion/edit buttons, stable UUIDs and existing
15/13-point task/tab typography. The tab row shows only saved tags in creation
order — no `All` and no `Untagged` tab is rendered. Zero tags show one
selected `Todo` guidance tab and the empty message "No tasks yet"; an empty tag
shows "No tasks in this tag". Selection is presentation state in
`LocalTaskPresentation`, kept above page navigation; `.untagged` remains only
the internal filter behind the empty-vocabulary guidance state. Deleted tag
IDs and invalid selections are reconciled when the task surface returns (to the
first remaining tag, or back to the guidance state).

A selected tab is an accent-tinted filled capsule with semibold text; an
unselected tab is secondary text with a light hover fill. Selection itself is
the affordance — never a focus box. AppKit's square focus ring is suppressed
(`PulseFocusRingSuppressor` in `PulseFocusEffect.swift`); keyboard focus draws
a soft, shape-matched stroke or fill instead of a rectangle around the capsule
(`PulsePillTab`, `PulseIconButtonStyle`, `PulseRowButtonStyle`).

Under the list, a centered `+` icon button expands the inline composer in the
same footer slot: text field, Tags menu, New tag field, "Repeat daily"
checkbox, Add/Cancel. The tag row's trailing `+` menu offers "Add task in tag"
(one entry per saved tag, pre-selecting that tag) and "New tag…", which starts
a composer for a task that gets a brand-new tag. Editing an existing task keeps
its separate editor page, including its delete confirmation. A submission guard
is set at the button boundary before scheduling asynchronous saves, preventing
double creation clicks. Failed saves retain the draft. After confirmed
creation, keep a tab that already shows the task or reveal the earliest-created
tag of the new task so the row is visible. The draft is retained in the
observable presentation owner above page navigation; draft text is not cleared
on dismissal.

Completed tasks stay visible: dimmed, struck through, after the open tasks
under a small `Completed` heading, in stored order. Nothing is hidden or
auto-removed, and the JSON model always retains every task. While a toggle is
pending, the row shows a spinner and its checkbox is disabled; state updates
only after the store confirms the write, and a failed save follows the reloaded
state. Hovering a row reveals a trash button whose confirmation dialog must be
accepted before `deleteTask` runs; deletion from the editor is confirmed the
same way. Settings → Tasks owns tags only (`LocalTagSettingsView`, rename and
remove); removing a tag detaches its IDs and never deletes tasks.

Daily repeat: each task carries an optional `repeatsDaily` flag and a
`lastCompletedDay` (the local calendar day). The composer and editor share one
"Repeat daily" checkbox, and repeating rows show a small circular-arrows
marker. Completing a repeating task records the day of the click;
`LocalTaskController.resetRepeatingTasks()` runs on popover open
(`PulseAppDelegate`) and on task-surface appearance, re-arms repeating tasks
completed on an earlier day, is idempotent, and writes nothing when nothing is
stale. It is background maintenance: it must never raise `isSaving` (typing
stays enabled) and a successful run must never clear a visible error.

The visible task/tag editor reports editing state to the hover controller.
`setDismissalSuspended` cancels only hover departure while editing; AppKit's
transient outside click and status-item toggle remain immediate. Leaving a visible
editor releases suspension, and returning to a retained local draft reinstates it.
Editing retains the normal native motion lifecycle and 180 ms departure timing
after suspension is released. Settings actions use `PulseActionButtonStyle`:
compact borders/fills, primary emphasis for save, red tint for removal,
accurate disabled opacity and short hover/press color transitions. Respect
SwiftUI Reduce Motion, never scale/move the whole page for an action. General
preferences use switches. Keep existing handler semantics, native keyboard
focus and typography.

See [built-in persistence](../backend/builtin-tasks.md) for storage guarantees and
required failure, retry and schema-compatibility tests.
