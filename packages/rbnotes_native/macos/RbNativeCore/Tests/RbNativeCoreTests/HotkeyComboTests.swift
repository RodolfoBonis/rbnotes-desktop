import XCTest

@testable import RbNativeCore

final class HotkeyComboTests: XCTestCase {
  func testIdenticalCombosConflict() {
    let a = HotkeyCombo(keyCode: 49, modifiers: ["option", "shift"])
    let b = HotkeyCombo(keyCode: 49, modifiers: ["shift", "option"])
    XCTAssertTrue(a.conflicts(with: b))
    XCTAssertTrue(b.conflicts(with: a))
  }

  func testDifferentKeyDoesNotConflict() {
    let a = HotkeyCombo(keyCode: 49, modifiers: ["option"])
    let b = HotkeyCombo(keyCode: 15, modifiers: ["option"])
    XCTAssertFalse(a.conflicts(with: b))
  }

  func testDifferentModifierSetDoesNotConflict() {
    // ⌥Space (dictation) vs ⌥⇧Space (record note): different, no collision.
    let dictation = HotkeyCombo(keyCode: 49, modifiers: ["option"])
    let recordNote = HotkeyCombo(keyCode: 49, modifiers: ["option", "shift"])
    XCTAssertFalse(dictation.conflicts(with: recordNote))
  }

  func testFunctionModifierIsIgnoredForConflict() {
    // Carbon cannot express `function`, so combos differing only by it collide.
    let a = HotkeyCombo(keyCode: 49, modifiers: ["option"])
    let b = HotkeyCombo(keyCode: 49, modifiers: ["option", "function"])
    XCTAssertTrue(a.conflicts(with: b))
  }

  func testCarbonModifiersStripsFunction() {
    let combo = HotkeyCombo(
      keyCode: 49, modifiers: ["command", "function", "shift"])
    XCTAssertEqual(combo.carbonModifiers, ["command", "shift"])
  }
}
