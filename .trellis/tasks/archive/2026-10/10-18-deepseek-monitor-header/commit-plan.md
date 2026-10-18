# Authorized release commit plan

The user explicitly requested rebuilding/releasing the new version, local installation, and remote source publication. This authorizes the pending task commit and publication and supersedes the earlier no-push/no-install boundary.

1. `release: prepare Pulse 0.1.2`

   Includes the reviewed DeepSeek integration and corrected official icon, leading header, shared controls, tests, version metadata, release notes, specs, and task artifacts.

## Files in this commit

- `.trellis/spec/backend/codex-usage.md`
- `.trellis/spec/backend/deepseek-usage.md`
- `.trellis/spec/backend/index.md`
- `.trellis/spec/backend/release-delivery.md`
- `.trellis/spec/backend/vip-usage.md`
- `.trellis/spec/frontend/state-management.md`
- `.trellis/tasks/10-18-deepseek-monitor-header/check.jsonl`
- `.trellis/tasks/10-18-deepseek-monitor-header/commit-plan.md`
- `.trellis/tasks/10-18-deepseek-monitor-header/design.md`
- `.trellis/tasks/10-18-deepseek-monitor-header/implement.jsonl`
- `.trellis/tasks/10-18-deepseek-monitor-header/implement.md`
- `.trellis/tasks/10-18-deepseek-monitor-header/prd.md`
- `.trellis/tasks/10-18-deepseek-monitor-header/research/deepseek-official-mark.svg`
- `.trellis/tasks/10-18-deepseek-monitor-header/research/icon-correction.md`
- `.trellis/tasks/10-18-deepseek-monitor-header/research/integration-and-header.md`
- `.trellis/tasks/10-18-deepseek-monitor-header/task.json`
- `.trellis/tasks/10-18-deepseek-monitor-header/verification.md`
- `Pulse.xcodeproj/project.pbxproj`
- `Pulse/App/PulseAppDelegate.swift`
- `Pulse/Core/APIKeyConfiguration.swift`
- `Pulse/Core/DeepSeekConfiguration.swift`
- `Pulse/Core/Usage/MoneyFormatter.swift`
- `Pulse/Core/Usage/UsageController.swift`
- `Pulse/Core/VIPConfiguration.swift`
- `Pulse/Features/Home/AIStatusSummary.swift`
- `Pulse/Features/Home/DeepSeekStatusSummary.swift`
- `Pulse/Features/Home/HomeView.swift`
- `Pulse/Features/Home/ProviderStatusButton.swift`
- `Pulse/Features/Home/ProviderStatusLayout.swift`
- `Pulse/Features/Home/VIPStatusSummary.swift`
- `Pulse/Features/Settings/ProviderCredentialForm.swift`
- `Pulse/Features/Settings/SettingsView.swift`
- `Pulse/Features/Usage/Providers/DeepSeekProvider.swift`
- `Pulse/Features/Usage/UsageView.swift`
- `Pulse/UI/DeepSeekProviderIcon.swift`
- `README.md`
- `THIRD_PARTY_NOTICES.md`
- `Tests/PulseTests/DeepSeekRenderingTests.swift`
- `Tests/PulseTests/DeepSeekUsageTests.swift`
- `Tests/PulseTests/HomeViewRenderingTests.swift`
- `docs/releases/0.1.2.md`
- `docs/ui-layout-refactor.md`
- `project.yml`

## Pre-existing paths excluded

- `.workbuddy/`
- `docs/images/`

No installed app, private user data, credentials, binaries, staging directories, signing manifests, or unrelated paths are included.

## Validation

Full suite: 194 tests, 2 existing skips, 0 failures, independent review and strict formatting pass. Official mark correction passes focused rendering and exact vector review. Signed universal Release 0.1.2/build 6, mounted DMG/checksum, and installed executable/process checks pass. Native desktop inspection timed out; live account verification was not performed.

## Publication

Publish the work commit through non-forced fast-forward updates to the existing GitHub main branch, create v0.1.2 and the DMG/checksum release, then archive the task and record the journal in separate bookkeeping commits. No additional confirmation is needed for the user-authorized publication.
