import Foundation
import XCTest

@testable import Pulse

final class PulseLocalizationTests: XCTestCase {
  func testBothLanguagesContainTheSameNonemptyTranslationsAndFormatArguments() throws {
    let english = try table("en")
    let chinese = try table("zh-Hans")
    XCTAssertGreaterThan(english.count, 200)
    XCTAssertEqual(Set(english.keys), Set(chinese.keys))
    for (key, source) in english {
      let translated = try XCTUnwrap(chinese[key], key)
      XCTAssertFalse(translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
      XCTAssertEqual(try placeholders(in: source), try placeholders(in: translated), key)
    }
  }

  func testChineseDynamicStatusPreservesProviderAndUserSuppliedText() throws {
    let chinese = try localizedBundle("zh-Hans")
    XCTAssertEqual(PulseLocalization.string("Save and verify", bundle: chinese), "保存并验证")
    XCTAssertEqual(
      PulseLocalization.format("Connect %@", "DeepSeek", bundle: chinese), "连接 DeepSeek")
    XCTAssertEqual(
      PulseLocalization.format("Edit task: %@", "原样保留 100% 🚀", bundle: chinese),
      "编辑任务：原样保留 100% 🚀")
    XCTAssertEqual(
      PulseLocalization.format(
        "Restore the last deleted task (%lld available)", 12, bundle: chinese),
      "恢复最近删除的任务（还可撤销 12 项）")
  }

  func testUnknownSourceFallsBackWithoutTranslatingUserData() throws {
    let english = try localizedBundle("en")
    XCTAssertEqual(
      PulseLocalization.string("A user’s unchanged task 🌱", bundle: english),
      "A user’s unchanged task 🌱")
    XCTAssertEqual(PulseLocalization.string("Todo", bundle: english), "Todo")
  }

  func testListDeletionCopyExplainsCascadeAndSessionUndoInBothLanguages() throws {
    let chinese = try localizedBundle("zh-Hans")
    XCTAssertEqual(
      PulseLocalization.format("Delete “%@” and its %lld tasks?", "工作 100%", 12, bundle: chinese),
      "删除“工作 100%”列表及其中的 12 项任务？")
    XCTAssertEqual(
      PulseLocalization.format("Delete “%@” and its %lld tasks?", "Empty", 0, bundle: chinese),
      "删除“Empty”列表及其中的 0 项任务？")
    XCTAssertEqual(
      PulseLocalization.format("Delete “%@” and its %lld task?", "Work", 1, bundle: chinese),
      "删除“Work”列表及其中的 1 项任务？")
    XCTAssertEqual(
      PulseLocalization.string(
        "The entire list will be deleted. Undo keeps the last 20 deletions until Pulse quits.",
        bundle: chinese), "整个列表将被删除。退出 Pulse 前，可撤销最近 20 次删除。")
    XCTAssertEqual(
      PulseLocalization.format(
        "Restore the last deleted list and its tasks (%lld available)", 3, bundle: chinese),
      "恢复最近删除的列表及其任务（还可撤销 3 项）")
    XCTAssertEqual(
      PulseLocalization.string("Continue current edit", bundle: chinese), "继续当前编辑")
    XCTAssertEqual(
      PulseLocalization.string(
        "You are editing another task. Save or cancel that edit first; this list’s draft will be kept.",
        bundle: chinese), "你正在编辑另一项任务。请先保存或取消当前编辑；此列表的草稿会保留。")
    for language in ["en", "zh-Hans"] {
      let strings = try table(language)
      XCTAssertNil(strings["Remove “%@”? %lld tasks will move to Todo."])
      XCTAssertNotEqual(strings["Undo task deletion"], strings["Undo list deletion"])
      XCTAssertNotNil(
        strings[
          "This list changed since it was deleted. Resolve the conflict before trying Undo again."])
    }
  }

  private func localizedBundle(_ language: String) throws -> Bundle {
    let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
    return try XCTUnwrap(Bundle(path: path))
  }

  private func table(_ language: String) throws -> [String: String] {
    let bundle = try localizedBundle(language)
    let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
    let data = try Data(contentsOf: url)
    return try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
  }

  private func placeholders(in value: String) throws -> [String] {
    let regex = try NSRegularExpression(pattern: "%[0-9]*\\$?(?:lld|ld|d|@|f)")
    let string = value as NSString
    return regex.matches(in: value, range: NSRange(location: 0, length: string.length))
      .map { string.substring(with: $0.range) }.sorted()
  }
}
