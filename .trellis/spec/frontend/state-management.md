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
- The Settings surface refreshes login item status on appearance. Enabling or
  disabling calls `SMAppService.mainApp` through `LoginItemManaging`, then
  refreshes status. Opening the menu-bar popover needs no login-item query.
- The status item renders the bundled Codex icon plus the current `UsageRefreshState` title (`…`, percentage, `--`, or `!`). `showMenuBarLabel` only adds the word “Pulse”; it never hides the usage state.
- `CodexMenuIcon.png` is the monochrome template artwork for the macOS status bar only. Popover views use `CodexProviderIcon`, backed by the alpha-enabled `CodexColorIcon.png`, so the Codex mark keeps its supplied blue-violet color in both Aqua and Dark Aqua. Do not set the popover image to template rendering or reuse it for the status item.
- `DeepSeekProviderIcon` must preserve the actual DeepSeek whale geometry, including the belly, eye and tail negative spaces. The initial generic whale silhouette was rejected by the user. Reuse the shared native vector component on Home, Usage and Settings; preserve aspect ratio inside its existing frame and use the reference blue `#4D6BFE`. Obtain original vector geometry from the official source rather than approximating the mark. Keep attribution in `THIRD_PARTY_NOTICES.md` and inspect an enlarged render as well as the 14–18-point icons in both appearances.
- The popover uses one `HomeView.popoverSize` for both AppKit and SwiftUI and covers the entire hosting surface with one adaptive paper layer over the native popover material. The window tint and paper cards share the saved transparency. Forward the effective paper opacity through the nested page host so task cards receive it. Text and controls retain their adaptive foreground styles. Native show/close animation is enabled unless NSWorkspace reports Reduce Motion. Observe accessibility display changes and reread the setting before opening/closing. Animation duration and appearance are owned by macOS.
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

## Scenario: quick-panel navigation, Settings and guarded dismissal

### 1. Scope / Trigger
Home, provider-specific Usage and tag management share a 400-point-wide
popover capped at 520 points tall. Settings is a separate singleton 720 × 560 window. The approved
redesign intentionally replaces the older in-popover Settings architecture.

### 2. Signatures

```swift
enum PopoverPage: Equatable {
  case home
  case usage(ProviderID)
  case tagManagement
}
// Existing showHome/reset remain; showUsage carries the selected provider.
func showUsage(_ provider: ProviderID = .codex)
func showTagManagement()
```

AppDelegate owns the shared controllers, LocalTaskPresentation and Settings
window/session. See [UI presentation](ui-presentation.md) for window, connection,
interaction-hold and update preflight contracts.

### 3. Contracts
- Home has a localized date and marked title, with recording, focus and
  Settings controls beside it. The timer reserves a stable frame between its
  idle label and countdown. The full recording label fits in the toolbar.
  The provider band and task area remain separate.
  Providers share one 32-point row with icons and readouts. Preserve full
  values with intrinsic widths and scroll the row horizontally when needed.
  The menu bar remains Codex-only and follows UsageMenuFormatter.
- Clicking a configured provider refreshes only it and opens its Usage detail.
  Missing optional credentials offer connection configuration; unavailable and
  failure remain distinct from a successful reading. Never invent values.
- Paired Today Tasks fits the measured header and list, capped at 520 points.
  The list stays lazy as it crosses the short-list limit. Other pages and an
  active update banner use the full surface. Home reports the route, vault and
  staged version with the size. AppKit owns the viewport and applies the latest
  matching target once per main-queue pass without animating the window frame.
  Reuse a valid Home size on reopen.
- Settings navigation never lives in PopoverPage. Its ordinary reopen restores
  category and session inputs; contextual links select their provider/category.
- Opening waits for both 300 ms minimum guard and native popoverDidShow.
  Geometry includes button, content and whole window/arrow. Departure from all
  regions schedules one 180 ms close; re-entry cancels, duplicate exits do not
  move the deadline. Geometry is checked every 50 ms while shown and eligible
  for hover dismissal, then checked at the deadline. Native closing cancels
  tracking work. Explicit status clicks during closing toggle a pending
  reopening, consumed on the main queue after didClose resets the session.
  Settings and exit clear that pending request.
- Editor, keyboard navigation, native menu and native drag sessions each
  suspend hover close. A pointer click in the panel releases the keyboard
  hold. Releasing one source preserves the other holds. Final release resamples
  geometry and starts a fresh grace interval if outside. Outside-click/status
  toggle still use native transient dismissal.
- willClose stops hover work; didClose resets quick navigation to Home after
  native animation finishes. Settings state and all retained drafts survive.
- End the native field editor before replacing a route. Replace content
  immediately in one live host. Fade the new body for 140 ms, using the
  in-flight presentation opacity when interrupted. Same-route updates retain
  the host state and existing animation.
- Reduce Motion disables native popover animation and all custom transition
  animation. Geometry reports, control values and focus still update immediately.
- Keep the inline Add field mounted outside the scrolling rows. Add performs
  the native focus transfer before returning and retains a pending request
  until the window's first responder is the actual field editor. SwiftUI
  updates avoid writing values into an active field. Publish committed input
  and use the editing identity to reject callbacks from retired sessions.
- Quick Copy uses a local, atomic document. Only a successful write to the
  pasteboard can start the confirmation. A newer copy replaces the displayed
  entry and cancels the old expiry. Closing the page clears only feedback.
- Begin opening before refreshing credentials or task data. Read credential
  presence off the main thread and reject results superseded by a later read,
  save or removal. Keep ready task content visible across background loads.

### 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Pointer stays on button or arrow | Keep open after presentation/guard |
| Leaves all regions | Close after 180 ms if geometry still outside |
| Re-enters / duplicate exit | Cancel / retain original deadline |
| Menu extends outside panel | Menu lifecycle holds until it ends |
| Drag exits / Escape cancels | Retain hold / release real session |
| Menu ends while editor active | Editor still holds panel |
| Click DeepSeek | Open DeepSeek details, not Codex |
| Close panel on a subpage | Next open Home; drafts retained |
| Click during native closing | Apply final toggle intent after cleanup |
| Update ready on a compact Home | Expand once and show update actions |
| Open Settings during draft | Same app-owned draft remains available |
| Change key during refresh | Existing generation guard rejects old result |

### 5. Good / Base / Bad Cases
Good: inspect a provider then return to the same list and draft. Base: new user
can connect optional services without a false error. Bad: saved invalid key
cannot show Connected, and a menu/drag must not dismiss mid-operation.

### 6. Tests Required
Keep native hover/callback and provider formatting tests. Cover rapid toggle
parity, held reconciliation, short-list resizing and update staging,
navigation targets, overlapping holds and stale leases, 400-point header geometry,
720 × 560 Settings, opaque edges in solid mode, failed/large/multi-currency values and
light/dark × English/Chinese. Render pass is not live mouse/IME acceptance.

### 7. Wrong vs Correct

```swift
// Wrong: every provider opens the same page.
pages.showUsage()
// Correct: preserve the clicked service's identity.
pages.showUsage(.deepSeek)
```

## Built-in tasks

### 1. Scope / Trigger

The app delegate owns one `LocalTaskController` and one
`LocalTaskPresentation`, injected into Home and Settings. Tabs, quick entry, editing and
Settings use that shared state. The optional Obsidian Today surface shares one
`TodayTaskBridge` and one `TodayTaskPresentation` across Home and Settings. A
paired vault makes Today the only task surface and hides local tag management
in Settings. A missing heartbeat still shows Today with its sync status.
Disconnecting the vault restores the native interface and retained drafts.
Tests use isolated defaults and temporary stores.

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
- The selected tab ellipsis, context menu and searchable manager share tag
  rename/delete operations. Delete requires confirmation explicitly naming the
  list and task count, whole-list removal and session-limited Undo. Affected
  unfinished drafts block removal with Return to draft; check both a draft's
  destination and its existing task's source membership in the current document,
  including an edit being moved away. Enforce at submit as well as rendering;
  never strand a quickDrafts entry or overwrite a Todo draft.
  If another task editor is active while a quick draft blocks list deletion,
  explain that the current editor must be resolved first and offer Continue
  current edit. Do not promise to reveal a hidden quick draft while another
  editor still occupies the surface, or silently discard either draft.
- A centered circular Add task button follows all task rows inside the
  task ScrollView. It keeps a text accessibility label and help. Presentation
  owns expansion per list alongside retained
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
- Completed rows stay exactly where they are: dimmed/struck through, in stored
  order, with no section heading and no collapse state. Checkbox is
  disabled immediately. Keep its previous glyph for 150 ms, then show busy
  feedback if still pending. Use a static clock with Reduce Motion.
- Reserve delete-control width; hover/focus changes visibility without text
  reflow. Keyboard and context-menu actions reach delete. Row/editor delete
  has no confirmation and exposes Undo after confirmed removal. Controller
  history keeps 20 task/list deletion operations through pages/popover closure
  until process exit. One Undo restores an entire list, including empty tags.
  Share the Undo control with the tag manager/Settings and describe its receipt
  kind. Keep Settings/manager in place after restoration; preserve active editors
  and other drafts. Single-task restoration reveals its task when appropriate;
  missing original tags fall back to Todo for single-task receipts only.
  Revealing a moved/restored completed task selects its destination list and
  scrolls the target into view after the updated rows are present.
- Use existing adaptive opaque backgrounds, Pulse action/icon/row styles and
  fixed 400 × 520 popover. Respect Reduce Motion and do not animate whole pages
  for row actions. Settings uses its independent native categorized window.
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
| All rows completed | Each row stays in place, struck through; list height is unchanged. |
| Delete then another edit then Undo | Restore target only; subsequent edit persists. |
| Save/restore fails | Retain input/receipt and offer retry; no false success. |

### 5. Good / Base / Bad Cases

- Good: create an empty tag, add with Enter and return to the round Add task button,
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
