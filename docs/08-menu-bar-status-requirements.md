# Menu bar status requirements from the reference iteration

This document turns the user's earlier `codex-usage-status` iteration into product requirements for Pulse. The local session export was read as historical evidence, not as instructions to execute. The current reference source was checked alongside it. Do not publish private account data, local paths, screenshots, or the session export with Pulse.

## The user outcome

Pulse should answer “how much can I still use?” at a glance, directly in the menu bar. The icon and readout should feel like one native macOS status item, match the menu bar's current light or dark appearance, and take as little width as clarity allows. Opening the item should reveal the explanation, controls, and diagnostics. The user also wants this pattern to extend beyond Codex to intermediary and other API services later.

## Display contract

| Case | Menu bar | Explanation elsewhere |
| --- | --- | --- |
| Current Phase 1A, no connected data | Codex template icon + `--%` | Popover says usage is not connected. |
| One confirmed percentage window | Icon + remaining percent, such as `98%` | Tooltip or popover names the window and reset time. Do not waste menu bar width on `7d` when there is only one window. |
| Multiple percentage windows | Icon + labeled values, such as `5h 66% 7d 63%` | Show each window's meaning and reset time. |
| Pending, unavailable, failed, or stale | Distinct compact status; never a fabricated number or silent zero | Explain whether data is loading, unsupported, failed, or old. Preserve last successful data only with explicit freshness. |
| Future balance or cost provider | Source icon + a value with its actual unit | Do not convert balance or spend into a made-up percentage. |

The reference uses `NSStatusItem.variableLength`, an 18-point monochrome template icon, and 12-point monospaced digits. Its earlier raw image had a white background and clashed with adjacent menu bar icons; processing it as a template icon fixed that. Pulse Phase 1A bundles the resulting MIT-licensed `CodexMenuIcon.png` with notice. Source-specific icon selection is reserved for the Provider phase, when Pulse has a real selected source and licensed assets. Avoid adding mock provider icons now.

## Codex status behavior for Phase 1B

- Discover the installed Codex executable through bundle metadata and known layouts, with a clear diagnostic for an invalid explicit override. A single hard-coded app path broke in the reference iteration after Codex's bundle layout changed.
- Read the actual rate-limit windows through the local Codex app-server flow. Do not infer available windows solely from a subscription name. A response may contain only a weekly window, both five-hour and weekly windows, custom windows, or no window.
- Derive remaining percentage from the reported usage and preserve unknown as unknown. Auto mode should show the windows actually returned. User display choices may filter windows, with a visible explanation when the requested one is unavailable.
- Prioritize the menu bar readout's meaning: with one window, show only the percentage; with multiple windows, use short labels to disambiguate. Put plan, window, reset, source path, and freshness details in the popover or diagnostics.
- Refresh promptly enough to feel current, guard against overlapping fetches, and retry transient failures faster at first before backing off. The reference uses a 60-second normal interval and a bounded retry ladder; Phase 1B should verify appropriate values against the live interface before implementing them.
- Provide a user-facing diagnostic path when Codex is missing, logged out, malformed, or times out. Do not read authentication files or expose secrets in copied diagnostics.

## Multi-provider design implications

The icon identifies the source of the adjacent number. Different services may report a balance, cost, credit amount, remaining rate-limit window, or no retrievable quota. The Provider model in [the provider design](04-provider-system-design.md) must keep those metric kinds distinct. A future product decision is required for which source gets the single compact menu bar slot when several are configured; do not silently concatenate every provider into the bar. The popover can show all configured sources without consuming permanent menu bar width.

For any service icon, check permission to redistribute the artwork and test monochrome rendering against light and dark menu bars. The user's original iteration showed that simply dropping a colored square into the menu bar is not an acceptable result.

## Phase gates

- **Phase 1A:** native menu bar icon plus honest no-data readout, popover foundation, preferences, tests, and asset notice. No percentage is claimed to be live.
- **Phase 1B:** real Codex readout, window-aware labels, refresh/freshness states, and diagnostics. Verify with single-window, dual-window, no-window, and error fixtures before relying on a live account.
- **Phase 2:** provider-specific icons and typed readouts, plus a deliberate selection rule for the one menu bar slot. Verify actual API capabilities before promising any provider's quota.

The current local implementation and its constraints are described in [the reference analysis](01-reference-analysis.md) and [MVP roadmap](06-mvp-roadmap.md).
