# First-run flow (target for the MVP)

The current Phase 0 app only opens a placeholder window. This document describes the intended first-run experience once Provider and Obsidian features are implemented. The target is for an ordinary user to see useful status within five minutes, without terminal commands or knowledge of API endpoint names.

| Moment | User sees and does | Success / recovery |
| --- | --- | --- |
| 0:00 — Open Pulse | A menu bar icon opens a small welcome view: “Keep AI usage and tasks in sight.” Two choices: **Get started** and **Explore without connecting**. | The menu bar stays available. No automatic file scan or key request. |
| 0:30 — Connect Obsidian | **Choose your Vault** opens Finder folder selection; **Skip for now** remains visible. Explain “Pulse reads Markdown tasks in the folder you choose.” | Validate read access; `.obsidian` is a helpful default signal, but a custom configuration folder is possible. Let the user confirm a Markdown Vault without `.obsidian`. A skipped Vault can be added from Settings. |
| 1:30 — Choose task destination | If the user wants to add tasks, choose an existing note once; this step can wait until the first Add action. | No inferred Daily/Projects path. Missing or read-only note prompts reselection. |
| 2:00 — Add AI status | Show provider cards with an honest capability label: Codex local status, balance, or organization spend. The first supported provider can be connected in one focused step. | Codex: detect local installation/login. API service: explain key type, paste into a secure field, verify, and store in Keychain. Provider can be skipped. |
| 4:00 — See dashboard | Show connected provider metrics and ordinary tasks, with last-updated times and a Refresh action. | Empty states say what to do next. Missing permissions and service limits are explained as such, never rendered as 0%. |

## Language and recovery

- Say “Choose Vault,” “Connect service,” and “Last updated,” rather than exposing JSON-RPC, Keychain item IDs, file watcher names, or parsing rules.
- If Codex is absent or not signed in, offer **Open Codex** or **Try another provider**. If an API key lacks billing scope, show which metric cannot be read and how to continue with available capabilities.
- If the Vault moves or permissions change, preserve the connection card but pause task actions and ask the user to reselect the folder. If Markdown changed while Pulse was open, refresh before any write and show a conflict prompt when the exact task no longer matches.
- Every setup step is resumable. A person can use AI status without Obsidian or tasks without adding an API provider.

## Acceptance study

With five people unfamiliar with the project, measure time from first launch to one genuine provider status or one genuine Vault task. Success means at least four complete a useful connection in five minutes without a terminal, and all can identify what Pulse can read or change. The public MVP should also demonstrate both provider and task paths, even though an individual user may skip one.
