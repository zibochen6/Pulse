import AppKit

@MainActor
enum PulseApplicationMenu {
  static func makeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()
    let editMenuItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")

    // Accessory apps do not get the standard SwiftUI scene commands. Keep
    // Command-V on AppKit's responder chain so SecureField can handle paste.
    let pasteItem = NSMenuItem(
      title: "Paste",
      action: #selector(NSText.paste(_:)),
      keyEquivalent: "v"
    )
    pasteItem.keyEquivalentModifierMask = [.command]
    editMenu.addItem(pasteItem)

    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)
    return mainMenu
  }
}
