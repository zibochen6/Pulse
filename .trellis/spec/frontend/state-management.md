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
- Tasks is Home's main region and has one native local implementation in
  `Pulse/Features/Tasks/Local/`. The fixed tab row contains permanent default
  Todo (untagged only) plus independent custom tags, with no All/aggregate tab.
  Each task belongs to one logical list. A fixed tab-bar + creates empty tags;
  a separate centered + follows all scrolling task rows and expands quick entry.
  Completed tasks have a counted collapsible section. Delete is immediate with controller-owned
  Undo. Never fabricate sample tasks for empty/loading states. See Built-in
  tasks below for the complete interaction contract.
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

### 1. Scope / Trigger

The app delegate owns one `LocalTaskController`; Home owns a
`LocalTaskPresentation` above page navigation. Tabs, quick entry, editing and
Settings use that shared state. No task source preference/selector exists.
Tests use isolated defaults and a temporary store.

### 2. Interfaces and ownership

- `LocalTaskController` owns confirmed document, pending operations, errors,
  task-specific completion retries and bounded session deletion/undo history.
- `LocalTaskPresentation` owns selection, separate per-list quick drafts,
  existing-task edit state and tag-management input. Recreating a view or
  closing the popover does not discard this owner.
- `LocalTasksView` reports active editing through `onEditingChanged` to the
  hover controller. Focus/visible unfinished input counts; an idle empty
  composer or explicitly collapsed draft does not suspend departure dismissal.
- `PulseApplicationMenu.makeMainMenu()` supplies nil-target native text
  Undo/Redo/Cut/Copy/Paste/Select All commands. Text undo stays on AppKit's
  responder chain, never a task-deletion shortcut. The actual NSTextField field
  editor does not emit normal text-change delegate notifications for Undo/Redo:
  while editing, observe that editor's undo manager DidUndo/DidRedo notifications
  and synchronize the binding from its string. Detach observers on editing end
  and representable dismantle, so a shared field editor cannot update an old
  draft after focus moves.

### 3. Contracts

- Permanent Todo means untagged only; custom tags follow stored creation order.
  No aggregate tab. Deleted selected custom tags fall back to Todo. Selection
  does not mutate tasks. Selected capsules use accent fill and shape-matched
  keyboard focus, retaining 15/13-point task/tab typography.
- Put the + outside the tab ScrollView so overflow cannot hide it. Ensure the
  selected/new tag is scrolled into view. + opens independent tag-name input;
  Enter creates/selects an empty tag and focuses quick entry. Cancel writes
  nothing. Duplicate canonical names offer selecting existing tags. Todo is
  reserved and cannot be renamed/deleted/duplicated.
- Tab context menus and Settings share tag rename/remove operations. Remove
  requires confirmation explicitly stating tasks move to Todo and are kept.
- A centered task + follows all task rows and the Completed group inside the
  task ScrollView. Presentation owns expansion per list alongside retained
  drafts. Explicit expansion scrolls entry into view after mount and requests
  focus; ordinary list appearance never focuses hidden entry. Esc/collapse
  hides without discarding. Confirmed matching save clears and collapses the
  origin; failure preserves input. Explicitly guard AppKit marked-text
  composition so IME candidate confirmation cannot trigger task submission.
  The AppKit bridge combines its explicit enabled flag with SwiftUI's inherited
  `Environment(\.isEnabled)`; a parent's `.disabled` must disable its actual
  NSTextField. Refresh the accessibility label when the destination changes.
  Newly mounted fields retain an explicit focus request until attached to a
  window; ordinary hidden entry must not request focus. Bind quick entry to its
  captured origin and creation ID so a late native end-edit callback cannot
  resurrect a saved draft or write into a newly selected list. Conditional
  new-tag fields reject late binding writes after staging hides the field.
- List selection is single-choice; default is current list. Creation options
  start collapsed. The list menu's New tag action reveals name entry only when
  requested. Editor has Cancel / Edit task / Save in its header, a subtle
  multiline content area, compact list/repeat property rows and Delete below.
  Explicit Save commits; Cancel discards only the edit. Create/edit may select
  one new tag. Confirmed edits that move a task reveal its destination.
- Capture stable creation ID, draft version and originating list before async
  submission. Duplicate intent is blocked. A late reply may clear only the
  exact saved version, not newer typing/another list. Switching lists stores
  and restores their individual drafts and expansion state. A retained hidden
  draft alone does not suspend hover dismissal. Failed save keeps retryable input and
  its original creation ID. A successful save that finds newer retained input
  must give that input a fresh creation ID; reusing a committed ID with divergent
  content causes `taskConflict`. Editor/tag pending guards likewise survive
  view remounts, and older results cannot clear newer versions of the intent.
- Completed rows are dimmed/struck through after open rows, under a counted
  disclosure heading even when no open tasks exist. Starts expanded; collapse
  is presentation only. Checkbox is disabled/spinner shown while pending.
- Reserve delete-control width; hover/focus changes visibility without text
  reflow. Keyboard and context-menu actions reach delete. Row/editor delete
  has no confirmation and exposes Undo after confirmed removal. Controller
  history keeps 20 deletions through pages/popover closure until process exit.
  Restoration reveals its task; missing original tags fall back to Todo.
  Revealing a moved/restored completed task expands its destination's Completed
  section and scrolls the target into view after the updated rows are present.
- Use existing adaptive opaque backgrounds, Pulse action/icon/row styles and
  fixed 360 × 510 popover. Respect Reduce Motion and do not animate whole pages
  for row actions. Settings controls remain native and compact.
- Daily repeat remains per-task. Popover open/surface appearance reset stale
  days without raising `isSaving` or clearing another error. Task-specific
  completion retry preserves original click day; draft-save errors retain the
  corresponding draft. See backend spec for transaction guarantees.

### 4. Validation & Error Matrix

| Condition | Required outcome |
| --- | --- |
| Custom tags exist with untagged tasks | Todo remains reachable and displays them. |
| Tag-name cancel / duplicate | No empty task; no duplicate tag; existing choice offered. |
| Enter during marked-text composition | Confirm text composition, do not save task. |
| Save pending while switching lists | Submission uses captured destination; other draft survives. |
| Later input before old save resolves | Old result cannot clear new text or redirect selection. |
| Popover closes / Settings visited | Drafts remain; returning reinstates relevant editing protection. |
| Collapsed draft or unfocused empty input | Normal pointer dismissal resumes; retained text stays available. |
| All rows completed | Counted Completed disclosure still appears. |
| Delete then another edit then Undo | Restore target only; subsequent edit persists. |
| Save/restore fails | Retain input/receipt and offer retry; no false success. |

### 5. Good / Base / Bad Cases

- Good: create an empty tag, add with Enter and return to the centered +,
  reopen a retained draft, move a task, delete another and Undo without reflow.
- Base: Todo always holds untagged tasks; empty custom tabs allow immediate entry.
- Bad: a late save returns after tab/draft changes. Preserve current input and
  selection while updating only confirmed storage and the matching saved draft.

### 6. Tests Required

Exercise real presentation transitions across lists/recreated views and stale
save responses, not duplicate copies of view logic. Assert default Todo plus
independent single membership, create/edit new tag, matching-draft clearing,
failed-save retention, completed count/collapse and editing-suspension state.
Assert success collapses only its matching origin, collapse/reopen preserves
input, and a newly mounted composer actually becomes first responder and is
visible in the native scroll viewport. Test Escape during marked composition.
Render empty/populated/completed/options/editor/tag-management/undo states in
Aqua and Dark Aqua at the fixed size; inspect representative images. AppKit
text-command tests exercise the actual TaskEntryField editor
Undo/Redo (both visible string and binding) and the first-responder action
contract. Marked-text unit coverage does not replace actual IME candidate
acceptance. Record native mouse/keyboard validation separately and explicitly
report when desktop automation is unavailable.

### 7. Wrong vs Correct

```swift
// Wrong: default guidance disappears when a custom tag exists.
if tags.isEmpty { showTodoTab() }

// Correct: Todo is always a real destination for untagged tasks.
showTodoTab()
showCustomTagTabs(tags)
```

Never unconditionally clear the currently bound draft after an awaited save;
match saved origin, identity and version first. Never restore a deleted task by
replacing an old whole-document snapshot.

See [built-in persistence](../backend/builtin-tasks.md) and
[the user-facing contract](../../../docs/builtin-tasks.md).
