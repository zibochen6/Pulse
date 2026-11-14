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
