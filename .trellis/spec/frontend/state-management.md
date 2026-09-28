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
- The popover uses one `HomeView.popoverSize` for both AppKit and SwiftUI, disables its show/close animation, and covers the entire hosting surface with adaptive opaque `windowBackgroundColor`. Section cards use opaque `controlBackgroundColor`. This prevents the desktop from flashing through the panel.
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
  func synchronize(statusButton: Bool, content: Bool)
  func entered(_ region: PopoverPointerRegion)
  func exited(_ region: PopoverPointerRegion)
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
- Tasks is Home's main, list-ready region. While Obsidian is unavailable it shows a compact disconnected row and Connect Obsidian routes to Settings' Tasks explanation. It never displays sample tasks, Memo, or Add Task controls.
- `PopoverPageController` is presentation state only. It does not start an integration or change a UserDefaults key. `popoverDidClose` resets it to Home so a later open is task-first.
- `NSTrackingArea` on both the status button and hosting view uses mouse entry/exit, active-always, and visible-rect tracking. `PulseAppDelegate` calls `beginOpening()` before `show`, then seeds tracked regions from actual geometry. During the one-second Opening state, enter/exit events update observations but cannot close the popover. At the end of Opening, reread status-button and content geometry; a stale exit around the initial click must not decide closure.
- The controller has explicit Closed, Opening, Interactive, and PendingClose states. When neither tracked region contains the pointer, PendingClose waits 400 ms and rechecks the status button and entire popover window (including its arrow) before closure. If geometry still contains the pointer despite absent entry events, it reschedules the check so eventual departure still closes. Re-entry immediately cancels the pending close.
- `popoverDidClose` resets Opening, PendingClose, and pointer state even when AppKit closed the transient popover. A second status-item click and an outside click retain their immediate AppKit behavior. The hover controller never opens the popover.
- The popover retains its opaque adaptive background and fixed `HomeView.popoverSize` across page changes.
- Home keeps the task region visually dominant within the fixed popover size. The Usage detail page scrolls for extra quota windows and long messages; no detailed Usage content appears on Home.

### 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Pointer moves from status item toward popover | Grace period allows entry; entry cancels the close. |
| Pointer stays on the clicked status item through Opening | Geometry resampling retains the panel, including after two seconds. |
| Pointer leaves both and stays outside | Close after 400 ms, provided current geometry still confirms outside. |
| Pointer re-enters before deadline | Cancel close. |
| Pointer stays over the popover arrow without a content entry event | Keep checking geometry; close after a later departure. |
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

Unit tests cover Opening protection, end-of-Opening geometry resampling, delayed close, re-entry cancellation, continued checking across window-only hover, and reset after system dismissal. Page tests assert Home → Usage, Home → Settings destination, Back → Home, and reset after popover closure. Render Home, Usage, and Settings in Aqua and Dark Aqua and assert opaque edges; cover single and multiple windows, loading, unavailable, and long failure text. Keep existing usage and preference tests. Runtime desktop checks are still needed for actual AppKit event delivery and click behavior. Do not infer duplicate same-click actions without observing their event order.

### 7. Wrong vs Correct

```swift
// Wrong: closes during the short trip from the menu bar button to the popover.
func mouseExited(with event: NSEvent) { popover.performClose(nil) }

// Correct: record the exit and let the shared controller close only after
// both tracked regions remain empty for the grace interval.
func mouseExited(with event: NSEvent) { hoverController.exited(.statusButton) }

// Wrong: leave Usage selected when AppKit dismisses the transient popover.
func popoverDidClose(_ notification: Notification) { hoverController.reset() }

// Correct: clear both independent states; the next open begins at Tasks.
func popoverDidClose(_ notification: Notification) {
  hoverController.reset()
  pages.reset()
}
```
