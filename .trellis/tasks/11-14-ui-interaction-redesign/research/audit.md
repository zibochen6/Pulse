# Audit evidence

- PulseDesignTokens:69–87 uses snappy everywhere; extraBounce 0 still includes preset bounce. HomeView:27–32 removes outgoing view instantly to avoid stale NSTextField lifecycle, exposing background during incoming fade.
- LocalTasksView:582–631 hides horizontal scroll affordances; :649–663 already has right-click CRUD. Store has no tag count cap. :323–334 leaves drafts keyed by deleted tags inaccessible. Duplicate Create remains enabled although submit returns.
- SettingsView:43–78 stacks five sections; two credential forms always open. ProviderCredentialForm:24 equates stored key with Connected. All provider clicks open untargeted Usage.
- AppDelegate updater predicate only checks taskEditorActive/popover.isShown. UpdateController:298–304 invokes installer before terminate; termination veto is too late. Home privately owns task presentation.
- Menus lack tracking holds. Drag protection relies on tagDropTarget, released on dropExited. Use real native drag end/cancel to avoid permanent locks.
- Baseline Debug build and 79 selected tests passed at /tmp/PulseUIAudit-20261114.xcresult. Tests emphasize render dimensions/opacity, not visual quality. CUA getApp timed out; installed app 0.1.7 build11. Preserve unrelated untracked docs/images and .workbuddy.
- References: https://developer.apple.com/videos/play/wwdc2023/10158/ and https://developer.apple.com/design/human-interface-guidelines/settings .
