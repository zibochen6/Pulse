# UI presentation, windows and lifecycle safety

## 1. Scope / Trigger
Use for shared visual controls, independent Settings, provider connection status,
session drafts, native menu/drag holds, localization and restart/quit routing.

## 2. Signatures
`SettingsWindowController` owns one 720 × 560 native window. `SettingsPresentation`
owns category, expanded providers and in-memory credential drafts. `ProviderID`
is codex/vip/deepSeek/antigravity. `ProviderConnectionState.resolve(hasCredential:configurationError:state:)`
maps the existing refresh result. `PulseExitPolicy` computes automatic-install,
pending-write and discard-confirmation decisions. `PopoverInteractionHolds`
aggregates editor/menu/drag sources and issues identity-checked leases.

## 3. Contracts
- AppDelegate owns one instance of each existing controller and the task
  presentation; do not create second stores/refresh loops for Settings.
- Settings ordinary reopen preserves category. Explicit provider/category links
  navigate there. Mark the settings window open before closing the popover to
  prevent an automatic-install idle gap. Closing the window retains session
  inputs, releases active focus and never quits the app.
- Credential text lives only in memory until an explicit Keychain save. It
  survives category changes; success/cancel clears its matching draft. No
  credential text in logs, preferences, snapshots or promotion fixtures.
- The opt-in Gemini card uses the Antigravity controller. Its percentage is
  the 5-hour bucket by ID. Its detail page keeps the shared Gemini weekly and
  Gemini 4 Argon weekly allowances visibly distinct.
- Stored key alone means configured, not connected. No key -> Not connected;
  loading with key -> Verifying; successful data -> Connected; failed/partial
  data -> Needs attention. Reuse existing credentialsDidChange generation
  handling, request timeout and refresh cadence.
- `hasUnsavedEdits` includes hidden/folded task and Settings inputs. It is not
  equivalent to current focus/hover suspension. `hasPendingWrites` also blocks
  restart. Auto-install requires both surfaces closed and neither condition.
- Every UI explicit restart/quit performs preflight before installer invocation.
  Continue editing cancels; explicit discard clears session inputs and proceeds
  once writes finish. Ordinary window close does not discard or prompt.
- The Home focus control observes an app-owned 30-minute session. It continues
  across popover closes and counts sleep toward its continuous-clock deadline.
  Completion plays one chime, cancellation is silent, and the status item
  continues to show Codex usage. Explicit quit/restart ends the in-memory
  session. A staged automatic update waits for the session to finish or cancel.
- Preserve native text responder-chain Undo/Redo, Cut/Copy/Paste/Select All.
  App commands add Settings, Close and Quit without hijacking text Undo.
- A pointer-opened popover starts with no focused action highlight. Custom
  buttons use a single inset indication during keyboard navigation on macOS
  14+. Apply focusEffectDisabled only to those buttons; use native focus on
  macOS 13 and keep native text-field focus in both cases.
- Holds are source-scoped. An old lease cannot end a later session after reset.
  NSMenu tracking brackets menu holds; native NSDraggingSource end handles drop,
  outside release and Escape. `dropExited` must not terminate a drag hold.
- Shared adaptive tokens own color, spacing and motion. Press and keyboard
  focus update immediately. Scope release and hover animation to the fill, and
  use a 140 ms opacity transition for semantic changes. Use zero-bounce
  settling for local options and reorder feedback. Geometry from background
  updates and the inline input's first focus take effect immediately.
- Share the 150 ms busy glyph for ongoing activity. Reserve the slot and update
  the true state and action availability immediately. An operation ending
  before the threshold keeps its previous glyph. Unmounting cancels pending
  feedback. Reduce Motion makes custom transitions immediate and displays
  static busy feedback.
- Tag dragging uses NSDraggingSession. Drive edge scrolling with the view's
  display link on macOS 14 and elapsed-time stepping on macOS 13. Store the
  current geometry for input. Publish only changed visual drop targets.
  Release the scroll driver and drag state at session end.
- The dashboard uses one adaptive paper layer over the native AppKit backdrop per
  window. Settings General and the menu bar panel share a 0–50 percent preference
  in 5-point steps, default 25. Zero, Reduce Transparency and detached render
  fixtures use opaque paper. The system override never updates the saved value.
  The window tint and paper cards share the transmission so their opacity does
  not compound into an effectively solid panel. Apply it to card fills while
  keeping labels, borders and controls legible. Render tests must sample inside
  visible cards as well as the window margins at low and high settings.
- The dashboard palette uses ink, pastel paper for provider
  cards, green selection, and separate semantic and keyboard focus colors.
  Apply the common paper perimeter through `pulsePaper`. Task lists share the
  square completion glyph and circular Add task button. Paired Today adds a
  corner fold and completion count, and includes the perimeter's insets in
  the short-list height reported to the popover.
- Preserve task list order and drafts. Keep the composer outside the scrolling
  rows. Quick Copy rows show
  saved names and reserve the trailing confirmation slot so the copy label
  can change without shifting the row or its actions.
- English/zh-Hans resources follow system language. Localize computed strings
  as well as SwiftUI literal labels. Keep user data, provider IDs, currency codes,
  storage keys and accessibility identifiers invariant. Todo is a reserved name.
- Promotion renders real product components with isolated task/preferences and
  synthetic provider data. Label samples, disable live services/updates and
  never include real account data. Test renders are separate from runtime proof.
- `PulseRuntimeServices` must also isolate the app delegate's test host, not
  just individual test fixtures. With `PULSE_DISABLE_LIVE_USAGE=1`, credential,
  usage, login-item and updater dependencies are inert. Manual refresh, opening
  the popover or clicking a test-host control must not escape that boundary.
  Select dependencies before constructing live clients.
- Reorder completion must reconcile `pendingTagOrder` against stored tags in
  the operation completion path, independently of mounted views. Navigating
  away before success must not leave a permanent pending-write/quit blocker.

## 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| Settings opened repeatedly | Same window and shared controller identities |
| Invalid saved key | Needs attention, never Connected |
| Switch category/close with input | Preserve session draft |
| Hidden draft or pending write | Automatic installation remains blocked |
| Cancel explicit restart/quit | No installer or termination side effect |
| Menu ends during drag/editor | Other source still holds panel |
| Old end callback after reset | Does not release new lease |
| Reduce Motion press | No instantaneous scale change either |
| Chinese dynamic message | Correct localized format with all arguments |

## 5. Good / Base / Bad Cases
Good: save and verify a service, see its true status, revisit Settings at the same
category. Base: unconfigured service offers Connect. Bad: invalid key looks
connected, a hidden draft is lost during auto-install, or cancelled drag locks
the popover open forever.

## 6. Tests Required
Connection-state matrix; singleton window/open-close and explicit destination;
cross-category drafts; automatic install surface/dirty/pending matrix; cancelled
restart before installer; overlapping/stale holds; 100-tag navigation and draft
delete guards; format/key localization tests; rendered real sizes in both themes
and languages. Record native mouse/keyboard/IME checks and inaccessible tools
honestly rather than inferring success from screenshots.

For native render tests, measure SwiftUI layout through passive anchor
preferences (as with provider-header bounds). XCTest hosting windows may omit
virtual SwiftUI accessibility nodes even when the visible app exposes them.
Do not treat an absent in-process AX node as proof a control was not rendered,
or assume a SwiftUI identifier is copied onto a bridged NSTextField. Keep
geometry assertions independent from native input/focus assertions.

The opt-in `UIDemoExportTests` export accepts
`TEST_RUNNER_PULSE_UI_DASHBOARD_STILLS_ONLY=1` to render Home, Settings, Quick
Copy, all provider details, tags and recording edits in both appearances without
recording motion frames. Pass `-testLanguage` and `-testRegion` alongside the
fixture language to localize system-formatted dates and static SwiftUI text.

## 7. Wrong vs Correct
```swift
// Wrong: a key exists, so the account must work.
let connected = configuration.hasAPIKey
// Correct: availability and the existing refresh result jointly determine UI.
let state = ProviderConnectionState.resolve(
  hasCredential: configuration.hasAPIKey, state: usage.state)
```

Never start an update installer and only then ask whether unsaved edits may be
discarded. The decision belongs before `restartToUpdate()`.
