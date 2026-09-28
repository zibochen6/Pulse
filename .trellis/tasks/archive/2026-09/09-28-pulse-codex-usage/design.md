# Design

## Boundary
`CodexProvider` owns CLI discovery, app-server lifecycle, and decoding. A provider-neutral `UsageSnapshot` owns quota windows and future metric variants. A main-actor usage controller owns refresh state. The AppKit delegate formats the current snapshot for the status item; `HomeView` renders the same state.

## Protocol
Start the installed `codex app-server --listen stdio://` process. Write newline-delimited `initialize` (id 1), `initialized`, then `account/rateLimits/read` (id 2). Read complete lines and correlate id 2, separating a JSON-RPC error from missing/malformed data. Apply a bounded timeout and clean up the process. Do not inspect private Codex auth files. CLI lookup honors `CODEX_BIN`, then Codex.app bundle layouts and common PATH locations.

The returned `rateLimitsByLimitId["codex"]` is preferred; use legacy `rateLimits` when appropriate. Never substitute a different limit ID for Codex. Parse `usedPercent`, duration minutes, and reset Unix seconds. Clamp displayed remaining percentage to 0–100. Use actual windows to determine one versus multiple labels; do not infer from plan type.

## State and display
The refresh controller has loading, success, unavailable, and error states. It starts at launch, refreshes every 60 seconds, and permits manual refresh from the popover. A failed refresh must not invent a value or imply stale data is current. One window displays e.g. `98%`; two display e.g. `5h 66% 7d 63%`.

## Verification
Synthetic JSON fixtures cover legacy and multi-limit shapes, no windows, malformed payload, and server errors. A mock provider verifies refresh transitions. Xcode build/test are required; a manual app launch checks the menu bar and popover when desktop interaction is available.
