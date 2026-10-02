# Design
LocalTask/TaskTag/LocalTaskDocument (UUID identities and schema version) are separate from Dashboard. LocalTaskStore serializes transactions on a shared background queue and atomically replaces JSON; controller publishes only confirmed state. TaskSourceConfiguration migrates existing bookmark installations to Apex and others to local, persists explicit source. Home routes to independent LocalTasksView or existing TasksView. Settings owns source selection, existing Apex controls, and tag management. Editing callback connects to a minimal hover suspension flag without changing transient behavior. Tests inject defaults and storage URL, never use real persistent tasks/config.

## Apex creation follow-up boundary
The behavior gap is absence of creation on the imported source; it lives in
DashboardFileStore/Controller and TasksView, not local JSON. Add a typed request
with a stable creation identity and selected column/card anchor. The service
resolves a unique destination in latest parsed bytes, inserts a new unchecked
line without regenerating the document, coordinates/serializes and verifies
persisted data. If a stable block ID is needed for safe retry after uncertain
save, generate it only for the new task and validate duplicate IDs strictly.

Retain the Apex draft in a presentation owner above navigation, choose the
active column plus explicit card, publish only verified saves, preserve draft
on failure and guard late responses after selecting another file. Existing
checkbox writes, parser formats and default task source remain supported.
Use the current editor hover suspension callback; do not rewrite the popover.

Settings gets a reusable compact native-looking button style with role-aware
fills/borders and hover/press feedback respecting Reduce Motion. This affects
control visibility, not overall typography or page layout. No API/provider
behavior changes. Verify temporary-file creation/duplicate/error/concurrency
flows and inspect synthetic light/dark editor and Settings images.

## Dashboard reconnect follow-up
The current chooser waits exclusively for a close delegate callback. Retain
that normal handoff but also inspect actual popover/window visibility while
waiting; only present after both are invisible. If closure does not complete,
release the busy state with a retryable inline error. Request explicit closure
from AppKit, then defer native panel presentation outside the close callback.
Reselection increments an observable source generation so an old draft cannot
hide parse/read errors while the Home task view is unmounted. Preserve ordinary
refresh/navigation drafts, task source preference, native animation and hover.

## Inline creation boundary
TasksView always retains its current list, with DashboardTaskEditor rebuilt as
a compact footer composer. LocalTasksView likewise retains its list for creation
while existing edit/delete behavior stays available. Default Apex destination
uses the active column and existing group; native menus select column/group and
existing hashtag suggestions. New Apex tags are ordinary supported Obsidian
hashtags appended only to the new task text, never a change to parser/schema.
Local tags retain their independent JSON semantics. Stable drafts/request IDs,
confirmed-save publication, inline retry and edit-hover suspension are retained.
Only task presentation/views, synthetic tests and docs change; no provider,
parser, file writer or overall popover layout redesign.
