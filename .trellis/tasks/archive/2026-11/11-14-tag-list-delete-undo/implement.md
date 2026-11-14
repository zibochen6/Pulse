# Execution

1. Backend implementer: receipt/mutations/controller and storage/controller tests.
2. Frontend implementer: confirmation, shared Undo surfaces, original-task draft
   guard and localized strings/render tests. Coordinate receipt enum with backend.
3. Root: docs/spec sync, project generation when required, focused then full
   tests, localized tests, and independent check agent. Preserve unrelated files.
4. Commit task-owned changes, fast-forward main, publish/install 0.1.9/build13
   through scripts/release.sh only after checks. Archive and record delivery.

Checks: swift-format on changed Swift; xcodegen for new test files; xcodebuild
Debug test on arm64; focused Chinese localization/render tests; universal signed
release pipeline and 18 release-safety shell checks. Never run competing test
hosts. Root owns derived-data and test scheduling.
