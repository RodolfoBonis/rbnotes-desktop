import Foundation

/// Pasteboard abstraction (string-keyed types) so the snapshot/restore logic is
/// pure Foundation and unit-testable without AppKit. The plugin provides a thin
/// `NSPasteboard` adapter.
public protocol PasteboardLike: AnyObject {
  /// Monotonic counter bumped by every pasteboard mutation (ours or others').
  var changeCount: Int { get }
  /// Current contents as an ordered list of items, each a type → data map.
  func readItems() -> [[String: Data]]
  /// Clears and returns the new change count.
  @discardableResult func clear() -> Int
  /// Writes [text] as a single `public.utf8-plain-text` item, additionally
  /// tagged with each type in [transientTypes] (empty data) so clipboard
  /// managers skip it.
  func writeTemporaryString(_ text: String, transientTypes: [String])
  /// Replaces the contents with [items].
  func writeItems(_ items: [[String: Data]])
}

/// Transient/concealed markers so clipboard history tools ignore the text we
/// stage for the synthetic paste. See http://nspasteboard.org.
public enum PasteboardMarkers {
  public static let transient = "org.nspasteboard.TransientType"
  public static let concealed = "org.nspasteboard.ConcealedType"
  public static let all = [transient, concealed]
}

/// Snapshot/restore orchestration for the synthetic-paste flow.
public enum PasteboardManager {
  /// Captures the current contents.
  public static func snapshot(_ pasteboard: PasteboardLike) -> [[String: Data]] {
    pasteboard.readItems()
  }

  /// Stages [text] (marked transient/concealed) and returns the change count
  /// observed immediately after the write, to be passed to [restoreIfUnchanged].
  public static func writeTransient(
    _ text: String, into pasteboard: PasteboardLike,
    transientTypes: [String] = PasteboardMarkers.all
  ) -> Int {
    pasteboard.clear()
    pasteboard.writeTemporaryString(text, transientTypes: transientTypes)
    return pasteboard.changeCount
  }

  /// Restores [snapshot] only if the pasteboard has not changed since our write
  /// (`changeCount` still equals [expectedChangeCount]); i.e. the user or
  /// target app has not copied something new in the meantime. Returns whether
  /// the restore happened.
  @discardableResult
  public static func restoreIfUnchanged(
    _ snapshot: [[String: Data]], into pasteboard: PasteboardLike,
    expectedChangeCount: Int
  ) -> Bool {
    guard pasteboard.changeCount == expectedChangeCount else { return false }
    pasteboard.clear()
    if !snapshot.isEmpty { pasteboard.writeItems(snapshot) }
    return true
  }
}
