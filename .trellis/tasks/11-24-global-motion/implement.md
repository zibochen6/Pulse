# Implementation and validation

1. Compare 0.1.26 and the candidate using the same visible native fixture and Release configuration. Use 300 or more tasks, a compact paired Today list, many tags, long localized text and sample phase changes. Capture actual Animation Hitches and SwiftUI activity on the built-in Retina and external displays.
2. Implement the host lifecycle, one dimension target per run-loop pass and native route transitions. Cover rapid status toggle parity, update-banner fit, focus and Reduce Motion.
3. Implement stable list nodes, composer and checkbox feedback, edge autoscroll and common control feedback. Cover pending/retry paths, draft recovery and real motion differences during continuous scrolling, typing, dragging and phase changes.
4. Run full XCTest and the focused native fixtures. Report active interval hitch ratio, cadence and repeatable stalls with screen and build context. Target at most 5 ms/s per interactive interval. Fix reproducible regressions and retest.
5. Use a separate GPT check on the finished diff and measured evidence. Update the two presentation specs and relevant motion documentation, commit, archive the task, then run scripts/release.sh for the next upstream patch. Verify installed version and signature and compare all GitHub asset signatures and digests.

## Expanded verification

- Capture first-key dispatch and responder ownership using isolated timing events without recording real keystrokes or drafts. Add English and Pinyin checks for rapid actual input in the paired and unpaired list. Verify that archived render tests do not stand in for native input.
- Include 50 or more synthetic Quick Copy entries, repeated quick actions, exact multiline contents, failed clipboard writes, restart, deletion and long localized labels.
- Preserve the separation between a trace of scripted tag-strip movement and an actual NSDraggingSession cancellation. Keep real native acceptance separate from screenshots or key events inserted directly into an editor.
- Audit the whole merged diff independently before release. Proof from the previous implementation remains historical until rerun on the integrated head.
