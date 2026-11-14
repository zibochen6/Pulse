# Proposed commit batch

The user approved this batch and explicitly requested publication and local installation on 2026-11-14. The original feature/documentation commits precede the release preparation and version commit.

## feat: redesign native UI, settings and tag interactions

- `Pulse.xcodeproj/project.pbxproj`
- `Pulse/App/PopoverContentTransition.swift`
- `Pulse/App/PopoverInteractionHolds.swift`
- `Pulse/App/PopoverPageController.swift`
- `Pulse/App/PulseAppDelegate.swift`
- `Pulse/App/PulseApplicationMenu.swift`
- `Pulse/App/PulseExitPolicy.swift`
- `Pulse/App/PulseRuntimeServices.swift`
- `Pulse/App/SettingsWindowController.swift`
- `Pulse/Core/APIKeyConfiguration.swift`
- `Pulse/Core/AppConfig.swift`
- `Pulse/Core/DeepSeekConfiguration.swift`
- `Pulse/Core/PulseLocalization.swift`
- `Pulse/Core/SecretStore.swift`
- `Pulse/Core/Update/UpdateController.swift`
- `Pulse/Core/Update/UpdateFeed.swift`
- `Pulse/Core/Update/UpdateInstallScript.swift`
- `Pulse/Core/Update/UpdateRelease.swift`
- `Pulse/Core/Update/UpdateVerificationError.swift`
- `Pulse/Core/Usage/UsageController.swift`
- `Pulse/Core/Usage/UsageSnapshot.swift`
- `Pulse/Core/VIPConfiguration.swift`
- `Pulse/Features/Home/AIStatusSummary.swift`
- `Pulse/Features/Home/DeepSeekStatusSummary.swift`
- `Pulse/Features/Home/HomeView.swift`
- `Pulse/Features/Home/ProviderStatusButton.swift`
- `Pulse/Features/Home/ProviderStatusLayout.swift`
- `Pulse/Features/Home/VIPStatusSummary.swift`
- `Pulse/Features/Settings/ProviderCredentialForm.swift`
- `Pulse/Features/Settings/SettingsPresentation.swift`
- `Pulse/Features/Settings/SettingsView.swift`
- `Pulse/Features/Tasks/Local/LocalTagSettingsView.swift`
- `Pulse/Features/Tasks/Local/LocalTaskController.swift`
- `Pulse/Features/Tasks/Local/LocalTaskStore.swift`
- `Pulse/Features/Tasks/Local/LocalTasksView.swift`
- `Pulse/Features/Tasks/Local/NativeTagDragSource.swift`
- `Pulse/Features/Usage/Providers/CodexProvider.swift`
- `Pulse/Features/Usage/Providers/DeepSeekProvider.swift`
- `Pulse/Features/Usage/Providers/VIPProvider.swift`
- `Pulse/Features/Usage/UsageView.swift`
- `Pulse/Resources/en.lproj/Localizable.strings`
- `Pulse/Resources/zh-Hans.lproj/Localizable.strings`
- `Pulse/UI/PulseActionButtonStyle.swift`
- `Pulse/UI/PulseDesignTokens.swift`
- `Pulse/UI/PulseSection.swift`
- `Pulse/UI/PulseSharedControls.swift`
- `Tests/PulseTests/DeepSeekRenderingTests.swift`
- `Tests/PulseTests/HomeViewRenderingTests.swift`
- `Tests/PulseTests/LocalTasksRenderingTests.swift`
- `Tests/PulseTests/PopoverInteractionHoldsTests.swift`
- `Tests/PulseTests/PopoverPageControllerTests.swift`
- `Tests/PulseTests/PulseApplicationMenuTests.swift`
- `Tests/PulseTests/PulseLocalizationTests.swift`
- `Tests/PulseTests/SettingsLifecycleTests.swift`
- `Tests/PulseTests/TagBarLayoutTests.swift`
- `Tests/PulseTests/UIDemoExportTests.swift`

## docs: document UI redesign and add bilingual native demos

- `.trellis/spec/backend/auto-update.md`
- `.trellis/spec/frontend/index.md`
- `.trellis/spec/frontend/state-management.md`
- `.trellis/spec/frontend/ui-presentation.md`
- `.trellis/tasks/11-14-ui-interaction-redesign/check.jsonl`
- `.trellis/tasks/11-14-ui-interaction-redesign/design.md`
- `.trellis/tasks/11-14-ui-interaction-redesign/implement.jsonl`
- `.trellis/tasks/11-14-ui-interaction-redesign/implement.md`
- `.trellis/tasks/11-14-ui-interaction-redesign/prd.md`
- `.trellis/tasks/11-14-ui-interaction-redesign/research/audit.md`
- `.trellis/tasks/11-14-ui-interaction-redesign/research/commit-plan.md`
- `.trellis/tasks/11-14-ui-interaction-redesign/research/review.md`
- `.trellis/tasks/11-14-ui-interaction-redesign/research/verification.md`
- `.trellis/tasks/11-14-ui-interaction-redesign/task.json`
- `README.md`
- `docs/07-community-launch-plan.md`
- `docs/auto-update.md`
- `docs/builtin-tasks.md`
- `docs/media/ui-redesign/README.md`
- `docs/media/ui-redesign/home-en-dark.png`
- `docs/media/ui-redesign/home-en-light.png`
- `docs/media/ui-redesign/home-zh-Hans-dark.png`
- `docs/media/ui-redesign/home-zh-Hans-light.png`
- `docs/media/ui-redesign/pulse-demo-en.gif`
- `docs/media/ui-redesign/pulse-demo-en.mp4`
- `docs/media/ui-redesign/pulse-demo-zh-Hans.gif`
- `docs/media/ui-redesign/pulse-demo-zh-Hans.mp4`
- `docs/media/ui-redesign/settings-en-dark.png`
- `docs/media/ui-redesign/settings-en-light.png`
- `docs/media/ui-redesign/settings-zh-Hans-dark.png`
- `docs/media/ui-redesign/settings-zh-Hans-light.png`
- `docs/popover-motion.md`
- `docs/task-first-ui-polish.md`
- `docs/task-ui-visual-polish.md`
- `docs/ui-layout-refactor.md`
- `scripts/README.md`
- `scripts/export-ui-demo.sh`

## Excluded existing work

- `.workbuddy/`
- `docs/images/`

These pre-existing untracked directories are not modified or included.

Task archive and journal bookkeeping follow successful delivery. The release extension also includes graceful-install script safety, focused shell regressions, release notes and README links for 0.1.8.
