# Implementation plan

1. [x] Add a distinct optional Pulse creation identifier to the parsed task model and rename the creation request's computed identifier accordingly; retain genuine Obsidian block IDs unchanged.
2. [x] Teach `ApexDashboardParser` to recognize only the exact adjacent Pulse HTML-comment marker and associate it with the preceding checkbox task. Preserve the current grammar for all other content.
3. [x] Update insertion and retry validation to write the clean task line plus sidecar marker, reject duplicate/malformed markers, and preserve the request identity across retries. Extend safe task relocation to use the new unique marker without conflating it with a block ID.
4. [x] Add fixture/temporary-file tests for clean labels, parsing/reload, exact marker association, idempotent retry, duplicate marker conflict, external insertion relocation, and actual Obsidian block ID compatibility.
5. [x] Update the task-creation guide and Apex write-back spec, including the no-automatic-legacy-migration boundary.
6. [x] Run focused parser/creation tests, full regression, app build, Swift formatting/lint, and `git diff --check`; inspect staged scope to exclude unrelated work.
7. [x] Commit only the verified Apex metadata fix and its relevant Trellis/docs/tests. Do not push.

## Validation results

- Focused Apex/parser/creation/controller/editor tests: 43 passed, 0 failed.
- Full regression suite: 168 passed, 2 existing tests skipped, 0 failed (170 total).
- Debug app build: passed.
- Strict `swift-format lint` passed for changed implementation files and changed creation/controller/editor tests. `ApexDashboardTests.swift` has existing formatting findings in unchanged areas; the same findings are present in the HEAD version. The newly added test block is formatted.
- `git diff --check`: passed.
- Automated persistence tests used temporary Markdown files only. No live Obsidian window was used for a visual check; the decisive evidence is the exact written checkbox-line bytes and round-trip parser results.

## Validation / rollback points

- First prove the emitted checkbox line itself contains no Pulse identifier before exercising UI/controller code.
- Verify the written temporary file after reparsing; do not use the personal Dashboard as a test target.
- Before commit, compare the index and worktree separately. Preserve unrelated uncommitted work byte-for-byte.
- If marker association is ambiguous or malformed, the parser/write path must reject or leave the task without a creation identifier; it must not guess or generate duplicate tasks.
