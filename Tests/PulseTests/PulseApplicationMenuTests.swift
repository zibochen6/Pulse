import AppKit
import XCTest

@testable import Pulse

@MainActor
final class PulseApplicationMenuTests: XCTestCase {
  func testApplicationInstallsPasteCommandAtLaunch() throws {
    let mainMenu = try XCTUnwrap(NSApp.mainMenu)
    let editMenu = try XCTUnwrap(mainMenu.items.first?.submenu)
    let pasteItem = try XCTUnwrap(
      editMenu.items.first(where: { $0.action == #selector(NSText.paste(_:)) }))

    XCTAssertEqual(pasteItem.action, #selector(NSText.paste(_:)))
    XCTAssertEqual(pasteItem.keyEquivalent, "v")
    XCTAssertEqual(pasteItem.keyEquivalentModifierMask, [.command])
    XCTAssertNil(pasteItem.target)
  }

  func testCommandVPasteUsesFirstResponderAction() throws {
    let mainMenu = PulseApplicationMenu.makeMainMenu()
    let editMenu = try XCTUnwrap(mainMenu.items.first?.submenu)
    let pasteItem = try XCTUnwrap(
      editMenu.items.first(where: { $0.action == #selector(NSText.paste(_:)) }))

    XCTAssertEqual(editMenu.title, "Edit")
    XCTAssertEqual(pasteItem.title, "Paste")
    XCTAssertEqual(pasteItem.action, #selector(NSText.paste(_:)))
    XCTAssertEqual(pasteItem.keyEquivalent, "v")
    XCTAssertEqual(pasteItem.keyEquivalentModifierMask, [.command])
    XCTAssertNil(pasteItem.target, "Paste must resolve through AppKit's responder chain.")
  }
  func testTextUndoAndRedoCommandsRemainOnResponderChain() throws {
    let editMenu = try XCTUnwrap(PulseApplicationMenu.makeMainMenu().items.first?.submenu)
    let undo = try XCTUnwrap(editMenu.items.first(where: { $0.title == "Undo" }))
    let redo = try XCTUnwrap(editMenu.items.first(where: { $0.title == "Redo" }))
    XCTAssertNil(undo.target)
    XCTAssertNil(redo.target)
    XCTAssertEqual(undo.keyEquivalent, "z")
    XCTAssertEqual(undo.keyEquivalentModifierMask, [.command])
    XCTAssertEqual(redo.keyEquivalentModifierMask, [.command, .shift])

    // Execute the same selectors against a real AppKit text editor. Text undo
    // must leave the task controller out of the responder chain entirely.
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
      styleMask: [.borderless], backing: .buffered, defer: false)
    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
    window.contentView = editor
    editor.allowsUndo = true
    window.makeFirstResponder(editor)
    editor.insertText("Draft text", replacementRange: NSRange(location: 0, length: 0))
    XCTAssertEqual(editor.string, "Draft text")
    XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(undo.action), to: window, from: undo))
    XCTAssertEqual(editor.string, "")
    XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(redo.action), to: window, from: redo))
    XCTAssertEqual(editor.string, "Draft text")
  }
}
