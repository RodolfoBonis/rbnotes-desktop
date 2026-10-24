import Foundation

/// A global-hotkey combination: a macOS virtual key code plus its modifier
/// names (the Dart `HotkeyModifier.wireName`s — `command`/`option`/`control`/
/// `shift`/`function`).
///
/// Pure and Foundation-only so the conflict rules can be unit-tested via
/// `RbNativeCore`. The AppKit/Carbon layer (`GlobalHotkeyManager`) uses this to
/// decide whether a requested hotkey collides with the dictation hotkey or with
/// another already-registered global hotkey before touching `RegisterEventHotKey`.
public struct HotkeyCombo: Equatable {
  public let keyCode: Int
  public let modifiers: Set<String>

  public init(keyCode: Int, modifiers: Set<String>) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  /// Modifiers that Carbon's `RegisterEventHotKey` can actually express.
  /// `function` is intentionally excluded: Carbon cannot register it, so two
  /// combos differing only by `function` register as the same system hotkey.
  public static let carbonModifierNames: Set<String> = [
    "command", "option", "control", "shift",
  ]

  /// The Carbon-relevant subset of [modifiers].
  public var carbonModifiers: Set<String> {
    modifiers.intersection(Self.carbonModifierNames)
  }

  /// Whether this combo would register as the *same* Carbon hotkey as [other]
  /// (same key and same command/option/control/shift set) and therefore
  /// collide at registration time.
  public func conflicts(with other: HotkeyCombo) -> Bool {
    keyCode == other.keyCode && carbonModifiers == other.carbonModifiers
  }
}
