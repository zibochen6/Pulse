# Design

Home shows its fixed toolbar, the task region and an independently observed AI footer. Keep app-native popup/Settings lifecycle and action controllers. The clip state uses its existing actionable entry. Reduce layout feedback by reporting a task area's natural height independently of provider state, coalescing AppKit resize requests.

Local and paired lists partition confirmed completed rows without changing their data or source ordering. Keep queued rows visible. The completed disclosure sits in the list below work, and a draft composer stays mounted outside the scroll view. Heights reported include the whole task area and return nil when the list needs the full content budget. Preserve focus and selected-list state.

Share a typed ProviderUsagePresentation across the footer, status item, overview and Usage detail. The projection consumes provider state, credential presence and activity, with buckets and currencies intact. Current values stay stable during refresh. Failed, missing and partial states depend on measured data and are never substituted with zero. Use exact valid reset and update dates, keeping known quota windows independent. Overview follows enabled service preferences. Prefer Codex for normal footer status; prioritize a known exhaustion or service error before it. No historical store or provider API change.

Add a single AI overview route, with Details returning to Overview and Overview returning to Home. Provider management opens the category at that provider. Use native text input, action styles and scoped observation. Keep current local schemas and the signed update path.
