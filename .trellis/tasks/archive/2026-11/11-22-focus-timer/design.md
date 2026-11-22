# Design

An app-owned main-actor controller publishes only the running state. It holds a continuous-clock deadline and a cancellable one-shot task. AppKit wake notifications reconcile an overdue deadline; cancellation and completion clear the deadline before further work. Home observes the controller, and the status item retains its existing usage display path.

Completion plays the system Glass sound with the AppKit beep as fallback. The automatic update gate consults the controller and re-arms its existing idle check after the session, including when a staged update already exhausted its polling window. Sessions are in memory and need no data migration.
