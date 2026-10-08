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

- The Home header contains Pulse identity, Settings gear, and one clickable `AIStatusSummary`. Its only data is the real Codex icon and `UsageMenuFormatter.title(for:)`: one window yields a bare percentage, multiple windows yield short labeled values, and loading/unavailable/failure yield `…`/`--`/`!`. Home has no usage reset time, update time, refresh control, or provider list. The AppKit menu bar uses the same formatter, but its behavior is unchanged.
- Clicking the summary calls `showUsage()` and displays full `UsageView` in a separate scrollable page. The existing Usage details and manual refresh remain there. Add Provider routes only to the Settings Providers explanation. Back from Usage or Settings calls `showHome()`.
- Tasks is Home's main region. `TaskSourceConfiguration` selects either built-in tasks or the independent Apex surface. Both connected sources offer Add Task with their own editor/storage; Apex creates a task only in an existing Dashboard group. Apex not-configured content routes to Settings. Neither source displays fabricated sample tasks.
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
| AI status is clicked | Show Usage detail with real quota windows, reset/update times, refresh, and error state. |
| Popover closes while Usage or Settings is visible | Reset page state; next open shows Home and Tasks. |
| Codex returns one weekly window or multiple windows | Home shows bare percentage or labeled short values respectively, with no window-selection setting. |
| Codex refresh fails | Preserve the existing explicit error state, not a fabricated percentage. |

### 5. Good / Base / Bad Cases

- Good: the user opens Pulse and sees a compact Codex status above the task list region, then clicks status to inspect full Usage detail.
- Base: the user views Settings or Usage, closes the popover, and sees Home on the next open.
- Bad: Codex refresh fails; Home shows `!`, while Usage detail explains the failure rather than repeating a stale percentage.

### 6. Tests Required

Unit tests cover the minimum guard plus native presentation completion, geometry resampling, short departure delay, duplicate exits, re-entry cancellation, missed events, arrow presence, Closing request gating and reset, and edit suspension. Check native NSPopover callbacks with animation enabled/disabled. Page tests assert Home → Usage, Home → Settings destination, Back → Home, and reset after completed closure. Render Home, Usage, and Settings in Aqua and Dark Aqua and assert opaque edges; keep existing usage/preference/task regressions. Actual mouse delivery and animation appearance still require desktop checks; do not infer visual acceptance from these tests.

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

## Apex Dashboard task state and checkbox persistence

`PulseAppDelegate` owns one `DashboardTaskController`. `TasksView` renders its
connection state and dispatches intents; it never performs file I/O. The left
checkbox and text opener are sibling buttons. Text opens Obsidian; checkbox
completion calls `setCompleted(_:task:)`, never the opener. Pending IDs are
registered synchronously; completion is confirmed from a verified disk snapshot.
Special markers are read-only. Source order, typography and hover behavior stay
unchanged. A loaded list remains mounted during refresh/save, preserving matched
row IDs and selection. Inline failures offer explicit retry or re-selection.

Completed rows are directly hidden from Home in both Apex cards and the current
built-in tag filter. Do not render a completed heading, count, disclosure or
expansion control. Preserve incomplete source order and every task in the
Dashboard/JSON model; this presentation never deletes or relocates data.
Pending writes keep the current row visible. Hide it only after applying a
verified saved/reread state; failed writes follow the reread source rather than
optimistically hiding a task. An Obsidian undo becomes visible on the next
refresh. Source changes, column/filter switches and reopen all use the same
incomplete-only policy. This is presentation only, not a preference or a new
persisted task classification.

Ordinary bookmarks remain in use in the non-sandboxed build. Selection generation
rejects undispatched intents and late UI replies after a new selection. A save
already accepted by the file worker may finish against its original file; it
never changes the newly selected file or publishes a stale result into it.
See [the persistence contract](../backend/apex-task-writeback.md) for source
locators, byte patches, serialization, conflict handling and test assertions.

### Dashboard file chooser handoff

`DashboardFilePicker` coordinates Idle → WaitingForClose → Choosing → Saving.
Selection first requests popover close and waits for `popoverDidClose`; a closed
popover skips the wait. Activate the accessory app, retain one `NSOpenPanel`,
present it with asynchronous `begin` outside the close callback and bring it forward. Do not run a modal
loop while the transient popover is still closing. Repeated status-item clicks
focus that panel rather than reopening Home or creating another chooser.

The handoff also checks actual popover and animated-window visibility every
50 ms. A missed delegate callback may advance only once both are invisible;
after two seconds of an unsuccessful close, clear the busy state and show an
inline retry error. Never reset Opening on an already-visible popover when
restoring Settings. Request explicit file-picker closure directly from AppKit,
not through potentially stale hover state. Late callbacks and repeat requests
must not present two panels. Test both missed-callback recovery and a real
still-visible timeout; do not equate a fake-panel test with desktop focus proof.

After cancellation or completed `saveDashboard(url:)`, restore Settings/Tasks.
Cancellation leaves the existing bookmark and selected task source intact. Saving
a bookmark does not implicitly switch from built-in tasks to Apex. Show this
explicitly when local is selected. The connection label must follow the actual
controller state, with read/parse/permission errors inline; bookmark existence
alone is not proof of a connection. Keep file selection testable via a fake panel
and isolated defaults/temporary Dashboards. Never overwrite the user's real
configuration for automated verification.

### Dashboard creation and Settings feedback

`DashboardTaskPresentation` lives above navigation beside local draft state. It
retains the original Dashboard snapshot, creation UUID, selected column/card and
text. New-task input is a compact footer under an always-mounted task list, not a
replacement page. Native menus/pickers choose column/card and optional plain
hashtags. The composer only dispatches `addTask(request:)`; the file store owns
insertion. Existing text hashtags and selected names deduplicate case-insensitively;
new tags modify only the new task text, never Dashboard metadata or old tasks.
Pending is registered synchronously by the controller; close a draft only after
verified success and only if its UUID still matches. Return to the destination
column. File re-selection clears a draft belonging to the old file, including
when the change happened while TasksView was unmounted. The presentation listens
to the controller's observable selection generation
above navigation, including failed reads/parses and explicit same-file choices.
Ordinary refreshes do not invalidate a draft. Errors retain input and
explain re-selection when needed. A column without cards cannot accept creation;
offer another existing column rather than inventing a new card.

The Apex editor reports `isEditing` through the same hover suspension callback as
the local editor. Outside clicks and status-item toggles still close normally.
Settings uses `PulseActionButtonStyle`: compact borders/fills, primary emphasis
for save, red tint for removal, accurate disabled opacity and short hover/press
color transitions. Respect SwiftUI Reduce Motion, never scale/move the whole page
for an action. General preferences use switches; source choice uses a segmented
control. Keep existing handler semantics, native keyboard focus and typography.

## Built-in tasks and source selection

The app delegate owns a `LocalTaskController` and `TaskSourceConfiguration` beside
the independent `DashboardTaskController`. Absent a saved source, an existing
Apex bookmark selects Apex on upgrade; otherwise built-in tasks is the default.
Source changes only choose a view and never convert, merge or delete data. Unit
host initialization uses isolated defaults and a temporary task store.

Local list rows use sibling completion/edit buttons, stable UUIDs and existing
15/14/13-point task/tab/group typography. Completed tasks remain in storage and
are hidden directly from Home without a completed section or count. Filters
are All, Untagged and named tags. The task editor retains a draft in an observable
presentation owner above page navigation; draft text is not cleared on dismissal.
Deleted tag IDs and invalid filters are reconciled when the task surface returns.
Creation uses a compact inline footer with existing/new tag choices and the
list/filters retained; editing/deleting an existing task keeps its current form.
After confirmed creation preserve a matching filter, otherwise show All so the
new task is visible. A submission guard is set at the button boundary before
scheduling asynchronous saves, preventing double creation clicks. Failed saves retain the draft.

The visible task/tag editor reports editing state to the hover controller.
`setDismissalSuspended` cancels only hover departure while editing; AppKit's
transient outside click and status-item toggle remain immediate. Leaving a visible
editor releases suspension, and returning to a retained local draft reinstates it.
Editing retains the normal native motion lifecycle and 180 ms departure timing
after suspension is released.

See [built-in persistence](../backend/builtin-tasks.md) for storage guarantees and
required failure, retry and migration tests.
