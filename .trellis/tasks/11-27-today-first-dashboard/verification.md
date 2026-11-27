# Verification

## Native and rendering checks

- The integrated macOS Release suite executed 328 cases. 323 passed, five opt-in
  cases were skipped, and none failed. The focused compact-height and paired
  composer tests also passed six consecutive repetitions each.
- The isolated task fixture sends the native first key and marked text. It
  checks that an AI refresh retains the original field editor, the composition
  and the live scroll view's offset. Sync fixtures exercise a queued action,
  conflict, retry and acknowledgement. Copy uses an isolated native pasteboard.
- Generated and inspected 52 offscreen renders in English and Simplified Chinese
  with Aqua and Dark Aqua. Coverage includes adaptive local and Obsidian Home,
  the AI overview and four service details, long multi-currency amounts,
  copy, tags, settings and recording outcomes. The two Home renders assert
  their actual reported compact height. The production test host skips status
  item and live service setup. The remaining native fixtures run offscreen.
- Independent GPT/Trellis review covered ordering, window sizing, native input,
  error recovery, settings routes and test isolation. Follow-up covered the
  measurement-only stack and the refresh-preservation assertion.

## Same-Mac offscreen comparison

Both versions run the same Release fixture on this arm64 Mac with windows kept
off the desktop. Baseline source is v0.1.30 at 8070d2b. The baseline-only test
patch carries the same fixture and leaves the test host quiet. There are 23
measured trials per scene and pair after removing the warm-up.

Each cell is median / p95 elapsed milliseconds from v0.1.30 to this candidate.
The second pair runs the candidate before the baseline.

| Scene | Baseline first | Candidate first |
| --- | --- | --- |
| Mount and draw local Home | 34.81 / 38.61 → 32.55 / 35.21 | 34.04 / 42.22 → 33.11 / 36.89 |
| Mount and draw Obsidian Today | 22.48 / 24.82 → 18.70 / 21.72 | 21.79 / 24.11 → 18.44 / 21.83 |
| Eight long-list scroll draws | 127.10 / 139.14 → 139.17 / 147.51 | 138.46 / 146.57 → 136.44 / 145.08 |
| Native first key, marked text and draws | 49.89 / 54.28 → 55.49 / 59.17 | 53.74 / 57.56 → 54.43 / 58.96 |
| Home to Codex detail and back | 90.16 / 95.02 → 103.37 / 109.22 | 96.62 / 101.05 → 101.97 / 110.93 |

Both Home mounts were faster in both pairs. Scroll results varied with run
order, and input was slightly slower in the two paired runs. The direct detail
round trip took longer in both pairs, including
after scoping provider observation to the active detail. These are offscreen
layout and drawing timings. The visible Instruments trace predates the request
to keep windows off the desktop and covers only v0.1.30. Candidate native
opening animation and displayed compositor hitch rates still need comparable
measurements.

## Release status

The release gate remains pending. The installed bundle passed strict signature
verification at 0.1.30, and GitHub Latest reported v0.1.30. The candidate remains
on its local implementation branch.
