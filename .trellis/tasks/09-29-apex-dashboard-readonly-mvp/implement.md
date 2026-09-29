# Implementation

1. Add immutable task models, strict parser, bookmark configuration, and a
   main-actor task controller with explicit connection states.
2. Replace the Tasks placeholder with state-specific read-only Apex content
   and add Dashboard selection to Settings.
3. Inject the controller through the app delegate and refresh it immediately
   before each popover presentation.
4. Add parser, bookmark/controller, page/rendering tests using fixtures and
   temporary files only.
5. Update README and Apex MVP documentation; review privacy boundaries.
6. Generate the Xcode project, build, test, inspect the diff, update any
   required Trellis specification, and commit without pushing.
