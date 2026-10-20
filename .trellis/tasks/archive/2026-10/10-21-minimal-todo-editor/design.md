# Design

Reuse LocalTaskPresentation, LocalTaskQuickComposer, LocalTaskOptions and LocalTaskEditor. Keep storage/controller unchanged unless a directly necessary regression fix is demonstrated.

Presentation owns per-list expanded state alongside quickDrafts. beginAddingTask expands and issues a focus/reveal request. Explicit collapse removes focus while retaining draft. Existing snapshot equality/creationID/selectionRevision guards determine whether success may reset/collapse the origin. Failure keeps state. A reopened or changed draft must not be hidden by an old response.

Put the add/composer region after completed rows in the task scroll reader, with stable scroll target. Explicit expansion/new tag scrolls it into view after mount. Avoid lazy-stack dismantling causing input/focus loss during editing. Retain successful task reveal behavior and keyboard-accessible plus with native button styles.

Editor uses one compact top toolbar, 16-point content insets, adaptive text background, existing system typography, multiline text, two compact property rows and low-emphasis destructive action. Remove redundant Task/Task options labels in editor. New-tag visibility is explicit draft state shared by quick and edit options; selecting existing destination hides/clears pending new-tag input consistently. No new dependencies or web UI.

Use existing accessibility identifiers where possible and add stable IDs for add/collapse and menu new-tag entry. Error retry remains explicit Save/Add; duplicate submissions disabled. AppKit marked-text protection and text undo observer remain intact.

Rollback: revert UI/presentation/tests/docs commits; no migration or data rollback needed.
