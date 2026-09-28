# Design: Apex Dashboard documentation phase

## Evidence boundary

Use the explicitly provided local Dashboard Markdown and the installed Apex Dashboard 1.4.4 manifest/bundle as read-only evidence. Treat the Markdown file as observed data, and the installed plugin code as evidence of that version's parser and writer behavior. Keep task text, absolute paths, settings, and credentials out of repository artifacts. Public examples use invented names and tasks.

## Document contracts

- Analysis separates observed file syntax from plugin-supported syntax and future assumptions. Describe YAML columns and body headings/cards/tasks without private labels or content.
- Parser design specifies a pure future read model and source-location metadata. It does not prescribe a writer. A one-based line number locates a snapshot only; optional block ID can provide an explicit Markdown anchor where present.
- UI design fits the existing task-first 360×510 popover. Column tabs come from Dashboard columns; cards stay within columns. Opening a task launches the source file through `obsidian://open?path=...`, with URI encoding and no line-level guarantee.
- Onboarding design uses explicit user choice of Vault and Markdown file. The file must be within the chosen Vault and validated as Dashboard-shaped. The four requested connection states cover the main flow; permission/read failure remains a distinct error reason and message.
- Writeback document analyzes the plugin's full-file serialization and backup behavior, concurrency, formatting, and the requirements for a separate future write phase. It authorizes no Vault writes.
- MVP document defines the smallest useful read-only integration and observable acceptance checks. It clarifies that the older general Obsidian roadmap is broader than this Apex-specific first step.

## Compatibility and privacy

The future reader should preserve file order and avoid inferring due dates or tags from the current sample. It should not assume a fixed Dashboard path. The first version refreshes on popover opening and an explicit action, not with a watcher. Test fixture text is entirely fictional and is not derived from the personal file.

## Verification and rollback

Review the seven deliverables together, inspect `git diff --check`, and search new tracked content for private path fragments or copied task phrases before commit. Since the task changes documents and a fixture only, rollback is the single local commit; no migration or runtime rollback is needed.
