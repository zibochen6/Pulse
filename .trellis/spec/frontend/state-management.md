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
- `@Published` emits during `willSet`. Subscribers that update AppKit controls must use the emitted value rather than re-read the stored property in the same callback.

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
