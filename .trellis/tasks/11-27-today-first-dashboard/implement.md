# Implementation and acceptance

1. Use an isolated worktree from 0.1.30 and build the isolated release profiling fixture as a baseline. Read current front-end, task sync and usage specs.
2. Implement the task partitions and natural-height reports. Integrate them with the Home layout and explicit route lifecycle. Implement the shared usage projection, overview and per-service detail. Maintain keyboard, drafts, background refresh, status item, and async handles.
3. Add targeted regressions and run full XCTest with en-US release defaults. Render isolated samples in en and zh-Hans, light and dark. Validate empty and full lists, pending/retry, first key and marked text, exact copy, focus, clipping, failures, disabled services, long amounts, and navigation. Run matching visible Instruments fixtures on the same display for the approved performance comparison and resolve regressions.
4. Run an independent Trellis check, record evidence and update the affected contracts. If accepted, fast-forward main and use scripts/release.sh for the next patch. Verify the installed version and signature, remote Latest and published asset hashes.
