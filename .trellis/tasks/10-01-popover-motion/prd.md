# Popover motion and response

## Goal
Make opening and dismissal feel native and responsive without changing the task UI or data behavior.

## Confirmed background
The existing popover disables animation, protects Opening for one second, waits 400 ms after pointer departure, and reconciles geometry every 100 ms. The user approved native motion and this plan. Built-in task changes and an independent untracked report must be preserved.

## Requirements
- Restore native NSPopover animation with opaque content. Respect Reduce Motion without changing system settings.
- Use a 300 ms minimum opening protection, also waiting for native presentation completion.
- Close after 180 ms outside both the button and popover; reconcile every 50 ms, including the arrow. Re-entry cancels, duplicate exits do not extend the deadline.
- Outside click and status-button toggling request close immediately. Closing cancels timers, rejects duplicate requests, and resets navigation only after dismissal completes.
- Keep task editing hover suspension and existing typography, layout, source selection, quota and task persistence.

## Acceptance
- No dismissal during presentation or opening protection; pointer retained on button keeps the panel open.
- Departure starts one 180 ms timer; return cancels it; missed events are corrected.
- Closing cannot restart Opening or issue another close; later opening starts cleanly.
- Build and all regression tests run with isolated data. Attempt desktop validation; document unavailable checks honestly.
- Update README and interaction contract; start the new build. No commit, push, release or private task edits.

## Dashboard picker regression follow-up
The user reports no response when reselecting an Obsidian Dashboard. The current
picker uses synchronous runModal without application activation or separation
from native popover dismissal. Fix the picker handoff and connection feedback:
wait for completed popover dismissal, activate Pulse, present one asynchronous
independent picker, restore Settings after cancel/selection, and show actual
loading/read/parse state. Preserve source selection and existing bookmark/data
semantics. Use fake panels and temporary files in tests, not the real Vault.
