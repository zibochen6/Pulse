import AppKit
import XCTest

@testable import Pulse

@MainActor
final class PulseApplicationMenuTests: XCTestCase {
  func testApplicationInstallsPasteCommandAtLaunch() throws {
    let mainMenu = try XCTUnwrap(NSApp.mainMenu)
    let editMenu = try XCTUnwrap(mainMenu.items.first?.submenu)
    let pasteItem = try XCTUnwrap(editMenu.items.first)

    XCTAssertEqual(pasteItem.action, #selector(NSText.paste(_:)))
    XCTAssertEqual(pasteItem.keyEquivalent, "v")
    XCTAssertEqual(pasteItem.keyEquivalentModifierMask, [.command])
    XCTAssertNil(pasteItem.target)
  }

  func testCommandVPasteUsesFirstResponderAction() throws {
    let mainMenu = PulseApplicationMenu.makeMainMenu()
    let editMenu = try XCTUnwrap(mainMenu.items.first?.submenu)
    let pasteItem = try XCTUnwrap(editMenu.items.first)

    XCTAssertEqual(editMenu.title, "Edit")
    XCTAssertEqual(pasteItem.title, "Paste")
    XCTAssertEqual(pasteItem.action, #selector(NSText.paste(_:)))
    XCTAssertEqual(pasteItem.keyEquivalent, "v")
    XCTAssertEqual(pasteItem.keyEquivalentModifierMask, [.command])
    XCTAssertNil(pasteItem.target, "Paste must resolve through AppKit's responder chain.")
  }
}
