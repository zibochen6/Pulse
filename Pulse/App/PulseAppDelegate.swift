import AppKit
import Combine
import SwiftUI

@MainActor
final class PulseAppDelegate: NSObject, NSApplicationDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let config = AppConfig()
  private let popover = NSPopover()
  private var preferencesSubscription: AnyCancellable?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    configureStatusItem()
    configurePopover()

    preferencesSubscription = config.$showMenuBarLabel
      .sink { [weak self] showName in self?.updateStatusButton(showName: showName) }
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }
    button.image = loadMenuBarIcon()
    button.imagePosition = .imageLeading
    button.toolTip = "Pulse · Usage not connected"
    button.target = self
    button.action = #selector(togglePopover)
    updateStatusButton(showName: config.showMenuBarLabel)
  }

  private func loadMenuBarIcon() -> NSImage? {
    // The bundled artwork comes from codex-usage-status; see THIRD_PARTY_NOTICES.md.
    let image: NSImage?
    if let url = Bundle.main.url(forResource: "CodexMenuIcon", withExtension: "png"),
      let bundledImage = NSImage(contentsOf: url)
    {
      image = bundledImage
    } else {
      image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "Pulse")
    }
    image?.size = NSSize(width: 18, height: 18)
    image?.isTemplate = true
    return image
  }

  private func configurePopover() {
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 360, height: 440)
    popover.contentViewController = NSHostingController(
      rootView: HomeView(config: config, onQuit: { NSApp.terminate(nil) })
    )
  }

  private func updateStatusButton(showName: Bool) {
    guard let button = statusItem.button else { return }
    // Show an honest no-data readout until a usage source is connected.
    let name = showName || button.image == nil ? "Pulse " : ""
    button.attributedTitle = NSAttributedString(
      string: " \(name)--%",
      attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]
    )
  }

  @objc private func togglePopover() {
    guard let button = statusItem.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      config.refreshLoginItemStatus()
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
  }
}
