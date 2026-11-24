# Verification

The baseline source is 505bfbe and the installed and public release is 0.1.25.
Gemini reviewed source, copy and interaction before implementation. A separate
GPT reviewer checked the finished diff and exercised focused tests.

- The latest full Debug suite ran 312 tests with 308 passing and four skipped.
  The skipped tests are one native WindowServer test and three opt-in fixtures.
- The focused task suite passed 88 tests. The shared feedback suite passed 11.
  The independent GPT suite ran 74 tests with 73 passing and the native test
  skipped on the locked console.
- The Release application built for arm64 and x86_64. Both localization files
  passed validation. The isolated exporter produced 40 stills across English,
  Simplified Chinese, light and dark.
- Native compositor capture initially worked on the 144 Hz display. A later
  run hit the locked console and stopped delivering display-link frames.
  The incomplete traces do not establish the comparative performance gate.

Remaining acceptance covers the unlocked console, repeatable profiles of the
same fixture on built-in Retina and external displays, and live status
clicks, native drag cancellation and composition. Merge, installation and
publication follow acceptance.
