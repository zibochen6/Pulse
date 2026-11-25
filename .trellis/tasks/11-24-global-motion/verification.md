# Verification on November 25

The published baseline is Pulse 0.1.26 at `b4e8557`. The integrated work is on
`codex/pulse-quick-copy-motion`. Gemini reviewed the state changes and copy,
and a separate GPT reviewer checked the diff and the follow-up fixes. The
review caught a retained field editor showing the previous tag name, clipped
Quick Copy insets, and hover dismissal while navigating with the keyboard.

## Input and data

- A native AppKit probe sent two key events to an isolated window. With
  deferred focus, the first event found no editor and only the second
  character reached the field. With synchronous focus, the first character
  reached the editor.
- The two product regressions send `.keyDown` to the native field editor in
  the same event turn as the Add action. They verify that AppKit retains
  marked text during a list update, including the boundary between 11 and 12
  paired tasks. The paired test uses an isolated vault.
- Six Quick Copy tests cover exact multiline and Unicode text in a named
  AppKit pasteboard, search and CRUD, restart, write failure and feedback
  expiry under repeated copying.
- The exporter produced 44 English and Simplified Chinese screenshots in
  both appearances. The existing paired Today test also renders its folded
  task card in both appearances and languages.
- The full Debug suite passed 320 tests. Three opt-in fixtures were skipped in
  that run. The stills and visible profiler fixtures passed separately.
  Release built for arm64 and x86_64 with the macOS 13 deployment target.
  Both localization files passed validation.

## Runtime and publication

The built-in display reported a maximum refresh rate of 120 Hz. The isolated
Release host profiled 320 tasks and 60 synthetic Quick Copy entries. Each
capture separates the warm-up from three timed trials. A callback timestamp
reports pacing separately from the compositor's hitch signal. The scripted
tag-strip sweep, AppKit marked-text test and screenshot export each have
separate coverage.

The median hitch rates are in milliseconds per second, with lower values
indicating less time spent hitching.

| Scenario | 0.1.26 light | Candidate light | Candidate dark |
| --- | ---: | ---: | ---: |
| Local long-list scroll | 172.47 | 28.75 | 36.13 |
| Inline typing | 953.16 | 265.55 | 268.76 |
| Completion and route changes | 782.20 | 319.88 | 317.77 |
| Scripted tag-strip scroll | 450.15 | 7.04 | 7.15 |
| Paired Today resize and scroll | 363.49 | 110.32 | 91.25 |
| Settings and background transparency | 749.94 | 301.94 | 232.77 |
| Quick Copy scroll and feedback | — | 182.14 | 195.94 |

The candidate is above the 5 ms/s acceptance target. Settings has repeatable
slider and route hitches. One Quick Copy light trial also recorded an
isolated 1.4-second hitch. The other trials did not repeat that duration.
The first Today resize during warm-up logged an extra SwiftUI geometry
notification. Time Profiler showed substantial main-thread hosting and lazy
layout work during scroll. Removing the redundant whole-card clip and
stabilizing row geometry reduced the long-list hitches.

Local artifacts are under
`/private/tmp/PulseQuickCopyMotion.GmIQk0` in `before-retina`,
`after-retina-v3`, `after-retina-dark`, `after-time-profile`, and `renders`.

Physical menu-bar input, a native drag cancelled with Escape, system Pinyin
and a 144 Hz external display still require acceptance. This Mac had the ABC
input source enabled and reported only the built-in display. AppKit marked
text in the tests validates the editor's composition lifecycle.

The production app and GitHub Release are still at 0.1.26. The installed app's
signature passed verification. Keep the task active until the remaining motion
and physical input checks pass.
