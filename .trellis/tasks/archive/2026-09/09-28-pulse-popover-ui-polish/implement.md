# Implementation checklist

1. Re-read current hover controller, app delegate, Home/Usage/Tasks and tests; create a fresh `codex/` branch from the clean checkout.
2. Make hover closure an explicit lifecycle state with a 1,000 ms Opening guard and existing 400 ms PendingClose. Re-sample pointer geometry at guard expiry; preserve transient outside-click and explicit toggle.
3. Trace actual open/close event ordering on a desktop if possible; address duplicate toggle only if observed. Remove temporary traces before commit.
4. Recompose Home into compact top Usage, dominant Tasks, and a fixed Connect Obsidian footer. Keep real Codex state and Settings navigation, and avoid fake task/provider controls.
5. Expand tests for hover lifecycle and Home rendering/layout states. Run XcodeGen only if source/project structure changes.
6. Update UI documentation and Trellis frontend state contract, including the recurring bug's cause and prevention. Run strict format lint, Debug build, complete tests and diff checks.
7. Inspect all changed paths for scope and commit `fix: stabilize popover interaction and rebalance home layout`; do not push. Archive the Trellis task and record the work session after the code commit.
