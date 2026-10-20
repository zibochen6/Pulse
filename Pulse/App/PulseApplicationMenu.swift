import AppKit

@MainActor
enum PulseApplicationMenu {
  static func makeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()
    let editMenuItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")

    // Accessory apps do not get standard SwiftUI scene commands. A nil target
    // keeps editing shortcuts on AppKit's responder chain, including field
    // editors and SecureField; task deletion must not intercept text undo.
    let commands: [(String, Selector, String, NSEvent.ModifierFlags)] = [
      ("Undo", NSSelectorFromString("undo:"), "z", [.command]),
      ("Redo", NSSelectorFromString("redo:"), "z", [.command, .shift]),
      ("Cut", #selector(NSText.cut(_:)), "x", [.command]),
      ("Copy", #selector(NSText.copy(_:)), "c", [.command]),
      ("Paste", #selector(NSText.paste(_:)), "v", [.command]),
      ("Select All", #selector(NSText.selectAll(_:)), "a", [.command]),
    ]
    for (title, action, key, modifiers) in commands {
      if title == "Cut" { editMenu.addItem(.separator()) }
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      editMenu.addItem(item)
    }

    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)
    return mainMenu
  }
}
