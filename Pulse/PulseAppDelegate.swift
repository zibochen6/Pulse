import AppKit

@MainActor
final class PulseAppDelegate: NSObject, NSApplicationDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var window: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    let icon = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "Pulse")
    icon?.isTemplate = true
    statusItem.button?.image = icon
    statusItem.button?.toolTip = "Pulse"
    if icon == nil { statusItem.button?.title = "Pulse" }

    let menu = NSMenu()
    let openItem = NSMenuItem(title: "Open Pulse", action: #selector(openPulse), keyEquivalent: "o")
    openItem.target = self
    menu.addItem(openItem)
    menu.addItem(.separator())
    let quitItem = NSMenuItem(title: "Quit Pulse", action: #selector(quitPulse), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)
    statusItem.menu = menu
  }

  @objc private func openPulse() {
    if window == nil {
      let created = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
      )
      created.title = "Pulse"
      created.center()
      let label = NSTextField(
        labelWithString: "Pulse is taking shape.\nUsage and tasks are coming later.")
      label.alignment = .center
      label.font = .systemFont(ofSize: 16)
      label.maximumNumberOfLines = 2
      label.translatesAutoresizingMaskIntoConstraints = false
      created.contentView?.addSubview(label)
      if let contentView = created.contentView {
        NSLayoutConstraint.activate([
          label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
          label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
      }
      window = created
    }
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func quitPulse() {
    NSApp.terminate(nil)
  }
}
