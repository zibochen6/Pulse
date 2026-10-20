# Design

## Data and ownership
LocalTaskStore remains the serialized, rereading, atomic verified JSON authority. Add independent createTag and restoreTask operations, single-list save validation and safe legacy normalization with byte-preserving backup before changed bytes reach disk. Default Todo is represented by empty tagIDs and never a stored tag. Legacy Todo tags are detached/removed; multi memberships choose first original document tag. Load validates original format before normalization, rejects corruption/new versions, and normalization must be idempotent and fail closed if backup/write verification fails.

Deletion receipt captures transaction-current task and ordering information (prefer neighbor IDs plus index). Extend snapshot with optional receipt rather than deriving from potentially stale UI; retry verification ambiguity must retain receipt and cannot lose undo. Restore rereads document, affects only target task, avoids duplicate/conflicting IDs, filters deleted tag membership and preserves intervening edits. Controller maintains bounded 20-item LIFO undo with operation guards.

Presentation owner stays above navigation. It owns draft-per-filter and separate edit/tag-management intents, stable creation IDs, submission origins and focused/dirty state. Single-choice tag selection uses optional tag UUID. Capture draft version/identity before saves, clear only matching saved input and never switch tabs on a stale response. Tag-creation drafts persist across view recreation. No aggregate UI filter.

## UI
Separate fixed tag bar (+ outside scroll), quick composer, and task ScrollView. Reuse shared Pulse controls, native fonts/adaptive colors. Collapsed options expose single-choice list + new tag + repeat. Use an AppKit text-field bridge if needed to explicitly guard marked text on submit. Provide initial focus only for explicit add/new-tag actions, avoid stealing focus on every appearance. Error and undo feedback remain reachable without displacing text. Tag menus and Settings share controller operations. Edit-save reveals moved task, delete returns list with Undo.

## Compatibility and recovery
Schema stays 1, old JSON arrays remain readable; future writes enforce <=1 membership. Original backup remains unchanged after repeated loads. Tests and native QA use isolated temp data (add a test-store launch override if needed); never launch development app against real tasks for acceptance. No release/push/install requested. Restore backup for rollback if required.
