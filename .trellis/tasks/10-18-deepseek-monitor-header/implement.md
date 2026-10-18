# Execution plan

## Gate

- [x] Task creation and planning approved.
- [x] Existing provider, credential, controller, header, settings, render tests, and build tooling inspected.
- [x] Official DeepSeek balance endpoint and response schema verified; evidence persisted in research.
- [x] PRD, design, and implementation/check manifests prepared.
- [x] Present final scope for review; obtain a subsequent explicit implementation approval (user: “实现”).
- [x] Run `task.py start` only after that approval.

## Ordered implementation

1. Implement the DeepSeek provider and typed Decimal decoder using injected HTTP and secret stores. Add focused fixtures/tests for request and error semantics, currencies, malformed values, and cancellation.
2. Add isolated DeepSeek Keychain configuration. Extract the minimal shared credential behavior if necessary, preserving VIP's public behavior and Keychain account. Test independent account operations and storage errors.
3. Wire the independent controller into app lifecycle, stale refresh, and the test-host gate. Ensure credential changes invalidate obsolete in-flight results and cannot be dropped by the single-flight guard. Add regression coverage for replace/remove during a fetch.
4. Add the DeepSeek icon, compact balance status, Usage section, and Providers settings. Keep all tests on injected synthetic stores/providers; update existing view initializers explicitly.
5. Shift header flexible space after the statuses, make the fallback row leading-aligned, and wrap whole indicators at measured widths. Bound an individually oversized quota label. Preserve fixed popover size and existing tasks/navigation.
6. Add meaningful layout/render checks and produce Aqua/Dark Aqua evidence with Codex, 88VIP `$104.22`, and CNY/USD DeepSeek sample balances. Inspect actual images and element frames; correct clipping/overlap before reporting done.
7. Update README, UI layout documentation, and the provider/frontend spec contracts. Regenerate the checked-in Xcode project after adding source files; inspect generated changes for unrelated churn.

## Validation commands

```sh
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/PulseDeepSeekDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/PulseDeepSeekDerivedData CODE_SIGNING_ALLOWED=NO test
xcrun swift-format lint --strict <Swift files changed by this task>
git diff --check
```

Run focused new tests while implementing, then one full suite after integration. The Xcode build is the Swift type-check gate. Do not broaden or repeat successful verification unless a new change/failure justifies it.

## Review and finish

Implementation steps 1–7, full quality verification, main visual inspection, independent `trellis-check`, and the spec update are complete. See `verification.md`. Local commit confirmation is pending; no code was committed, pushed, deployed, or installed.

The subsequent user-requested icon correction is also complete: official source geometry replaces the generic silhouette across all three views. Correction build, strict formatting, focused rendering tests, main visual comparison, and independent geometry review pass. No new scope approval is needed for this correction to the existing icon requirement.

- Dispatch `trellis-implement` for the approved artifacts, then an independent `trellis-check` pass over the full task scope. Dispatch prompts must start with the active task path and prohibit recursive implement/check dispatch.
- Review controller independence, provider currency correctness, real test-host isolation, and matching source/project references.
- Inspect representative rendered screenshots and any accessibility/layout measurements.
- Review new knowledge with `trellis-update-spec` and record the DeepSeek and header contracts.
- Present the repository-required commit plan only after concrete verified changes exist. Preserve and exclude pre-existing `.workbuddy/` and `docs/images/`; do not push, deploy, or replace the installed app without authorization.

## Risk and rollback points

- Credential configuration extraction must preserve the 88VIP Keychain account and existing save/remove behavior.
- Shared refresh lifecycle changes must preserve Codex and VIP single-flight, cancellation, stale refresh, and failure replacement behavior.
- Adaptive header changes must not change task draft ownership, source selection, native popover motion, or pointer-dismissal behavior.
- Revert only task-owned changes if a rollback is needed; do not touch unrelated untracked files or live account/task data.

## Authorized release extension

The latest user instruction explicitly authorizes code publication and local installation. It supersedes the earlier no-push/no-install scope boundary and pending local-commit-only confirmation; no additional process confirmation is needed for this requested delivery.

- [x] Bump to 0.1.2/build 6, regenerate Xcode project, add release notes and update README.
- [x] Independently check release metadata/docs consistency and relevant quality evidence.
- [x] Fetch remote state and verify non-forced fast-forward publication is possible.
- [x] Build universal Release, sign with the existing local Apple Development identity, verify signature/version/architectures.
- [x] Package DMG + SHA-256; mount read-only, verify exact app payload, and eject.
- [x] Back up and replace the installed app; launch `/Applications/Pulse.app` and verify its version, signature, executable hash, and running process path.
- [ ] Commit only task-owned source/docs; publish main/tag/release assets and verify GitHub state.
- [ ] Record release evidence/spec conventions, archive the task, record journal, and push bookkeeping without modifying release source/tag.
