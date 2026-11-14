import AppKit

@MainActor
enum PulseApplicationMenu {
  static func makeMainMenu(target: AnyObject? = nil) -> NSMenu {
    let mainMenu = NSMenu()
    let appMenu = NSMenu(title: "Pulse")
    let settings = NSMenuItem(
      title: PulseLocalization.string("Settings…"), action: NSSelectorFromString("openSettings:"),
      keyEquivalent: ",")
    settings.target = target
    appMenu.addItem(settings)
    appMenu.addItem(.separator())
    let quit = NSMenuItem(
      title: PulseLocalization.string("Quit Pulse"), action: NSSelectorFromString("requestQuit:"),
      keyEquivalent: "q")
    quit.target = target
    appMenu.addItem(quit)
    let appItem = NSMenuItem()
    appItem.submenu = appMenu
    mainMenu.addItem(appItem)
    let editMenuItem = NSMenuItem()
    let editMenu = NSMenu(title: PulseLocalization.string("Edit"))

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
      let item = NSMenuItem(
        title: PulseLocalization.string(title), action: action, keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      editMenu.addItem(item)
    }

    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)
    let windowMenu = NSMenu(title: PulseLocalization.string("Window"))
    windowMenu.addItem(
      NSMenuItem(
        title: PulseLocalization.string("Close Window"),
        action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
    let windowItem = NSMenuItem()
    windowItem.submenu = windowMenu
    mainMenu.addItem(windowItem)
    return mainMenu
  }
}
