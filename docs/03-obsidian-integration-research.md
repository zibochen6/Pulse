# Obsidian integration research

## Vault discovery

Obsidian describes a Vault as a local folder of Markdown text files. Its configuration folder is `.obsidian` by default, but users may choose another hidden name ([data storage](https://obsidian.md/help/data-storage), [configuration folder](https://obsidian.md/help/configuration-folder)). Users can place Vaults anywhere; Obsidian itself notices external file changes. Pulse should not infer the Vault from a folder name.

| Method | User experience | Implementation | Risk / decision |
| --- | --- | --- | --- |
| User chooses a folder | One clear Finder step; works for unusual locations and multiple Vaults | `NSOpenPanel` folder selection, inspect Markdown and configuration signals, remember chosen location | Best v1 default; user knows which Vault Pulse sees. |
| Scan common folders | Less work when it guesses correctly | Search home/cloud locations and disambiguate candidates | Privacy, permission, performance, and wrong-Vault risk; do not do this silently. |
| Read recently opened Vaults | Potential one-click suggestion | Depends on Obsidian's global state format and access | Fragile private app state; defer and keep explicit selection even if added. |

The selected Vault can be skipped during onboarding and changed later. Validate that the chosen folder is readable and inspect `.obsidian` as a strong default signal, but let the user confirm a Markdown Vault with an overridden configuration folder rather than reject it. Avoid nesting it inside another selected Vault. For a future sandboxed build, persist a security-scoped bookmark; the initial unsandboxed GitHub build still asks the user to choose the folder and keeps access limited to that choice.

## Layout and task discovery

The default `.obsidian` folder, or its configured replacement, holds settings rather than task source. Markdown notes can live at root or in arbitrary folders. Daily Notes is a core plugin whose new-file location and date format are configurable ([Daily Notes](https://obsidian.md/help/plugins/daily-notes)); `Projects` has no built-in meaning. Exclude the Vault configuration folder, non-Markdown files, and generated or hidden paths where appropriate, while allowing users to narrow task discovery by folders later.

A read-only local sample found a valid `.obsidian` folder and hundreds of ordinary checkbox lines across Markdown notes. It also had a directory named `Daily` while the core Daily Notes plugin was disabled. This is an aggregate observation only: no source path, note title, or note text is part of this repository. The scan made no writes.

## Todo parsing: first supported range

Recognize ordinary Markdown list checkboxes such as `- [ ] task` and `- [x] done`, including indentation and uppercase `X`. Preserve each task's note URL, line span, raw line, and completion state so UI actions can revalidate the source. Avoid matching examples inside fenced code, front matter, or comments. Obsidian's basic Markdown syntax includes task lists ([syntax](https://obsidian.md/help/syntax)).

The Tasks community plugin adds due/scheduled/start dates, recurrence, priority, custom statuses, and other metadata; its behavior is more than a checkbox ([Tasks date documentation](https://github.com/obsidian-tasks-group/obsidian-tasks/blob/main/docs/Getting%20Started/Dates.md), [Tasks user guide](https://publish.obsidian.md/tasks/Getting%20Started/Getting%20Started)). V1 may show such lines as read-only context if safely recognized, but must not toggle a line that carries plugin semantics until compatibility tests cover it. Offer **Open in Obsidian** for unsupported tasks. Do not strip metadata or treat a recurring task as a plain one.

For **Add task**, the user selects a destination note once during first use, then can change it in settings. Pulse must not create an assumed Daily or Projects path. If that note disappears or becomes unwritable, ask the user to choose another destination before writing.

## Safe Markdown synchronization design

1. Read UTF-8 bytes and record file identity, modification time, byte hash, newline style, and the exact target line. Display invalid-encoding files as unsupported; do not lossy-decode or rewrite them.
2. On Complete/Reopen, read the file again immediately. If file identity/content changed, locate the same unique line conservatively. If the task cannot be identified without ambiguity, stop and refresh the UI rather than overwrite edits.
3. Change only the checkbox marker in that line, preserving indentation, text, metadata, BOM if present, and line endings. Coordinate local writes where possible, write a temporary sibling file, preserve relevant permissions, then atomically replace. If replacement/revalidation fails, surface an actionable conflict and leave the original intact. External editors that do not coordinate can still race between comparison and replacement; test this and avoid claiming perfect conflict prevention.
4. Watch the selected Vault for external changes; coalesce bursts and rescan affected Markdown files. Reconcile by source path and line/content identity. Obsidian and cloud sync can edit concurrently, so a watcher is for freshness, not permission to skip pre-write comparison.
5. Test create, toggle, conflict, invalid UTF-8, CRLF, duplicate task text, symlinks, deleted notes, and cloud-sync-style replacement using temporary Vault copies only. The personal sample remains read-only.

No parsing, watcher, or writer is implemented in Phase 0.
