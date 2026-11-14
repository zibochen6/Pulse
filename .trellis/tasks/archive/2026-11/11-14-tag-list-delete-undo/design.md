# Technical design

- Extend storage with a transaction-current tag deletion receipt containing the
  tag, original index/neighbors, and receipts for every affected task. Capture
  before mutation on the shared serial queue; return/carry it through success
  and ambiguous write/verification failure. Delete tag and matching tasks as
  one staged document write.
- Add restore-tag/list mutation. Merge only receipt targets into latest stored
  state, restoring relative order from surviving neighbors/indices. Validate
  tag name and all UUID conflicts before persisting; identical retry is a no-op.
- Unify controller history with enum LocalDeletionReceipt { task, tag }; retain
  existing task receipt/snapshot interfaces where useful. Common receipt id,
  deletedAt and restore routing; latest operation is one Undo regardless of list
  size. Explicit pending/uncertain handling remains scoped to the deletion.
- Presentation uses the current document to detect an edited task's source
  membership as well as its new destination. Apply guard at the submit boundary,
  not just disabled-button rendering. Update Return to draft consistently.
- Reuse one undo presentation on Home and manager/Settings. Switch on receipt
  kind for truthful labels and reveal restored list/tasks without replacing an
  unfinished draft. Localize new confirmation, undo and conflict copy in en/zh.
- No real user-file writes during testing and no recovery guesses for prior
  detach operations. Existing release process handles verified 0.1.9 install.
