import AppKit

@main
enum PulseMain {
  @MainActor
  static func main() {
    let application = NSApplication.shared
    let delegate = PulseAppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) {
      application.run()
    }
  }
}
