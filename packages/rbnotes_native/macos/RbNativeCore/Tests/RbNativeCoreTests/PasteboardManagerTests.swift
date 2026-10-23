import Foundation
import XCTest

@testable import RbNativeCore

/// In-memory fake pasteboard that mimics `NSPasteboard`'s change-count
/// semantics: any mutation bumps `changeCount`.
private final class FakePasteboard: PasteboardLike {
  private(set) var changeCount = 0
  private var items: [[String: Data]] = []
  private(set) var lastTransientTypes: [String] = []

  init(initial: [[String: Data]] = []) { items = initial }

  func readItems() -> [[String: Data]] { items }

  @discardableResult func clear() -> Int {
    items = []
    changeCount += 1
    return changeCount
  }

  func writeTemporaryString(_ text: String, transientTypes: [String]) {
    var item: [String: Data] = ["public.utf8-plain-text": Data(text.utf8)]
    for type in transientTypes { item[type] = Data() }
    items = [item]
    lastTransientTypes = transientTypes
    changeCount += 1
  }

  func writeItems(_ newItems: [[String: Data]]) {
    items = newItems
    changeCount += 1
  }

  /// Simulates an external copy by the user / target app.
  func externalCopy(_ text: String) {
    items = [["public.utf8-plain-text": Data(text.utf8)]]
    changeCount += 1
  }
}

final class PasteboardManagerTests: XCTestCase {
  func testWriteTransientTagsItemAndReturnsChangeCount() {
    let pb = FakePasteboard(initial: [["public.utf8-plain-text": Data("old".utf8)]])
    let after = PasteboardManager.writeTransient("new text", into: pb)

    XCTAssertEqual(pb.changeCount, after)
    XCTAssertEqual(pb.lastTransientTypes, PasteboardMarkers.all)
    let item = pb.readItems().first
    XCTAssertEqual(item?["public.utf8-plain-text"], Data("new text".utf8))
    XCTAssertNotNil(item?[PasteboardMarkers.transient])
    XCTAssertNotNil(item?[PasteboardMarkers.concealed])
  }

  func testRestoreWhenUnchanged() {
    let original = [["public.utf8-plain-text": Data("original".utf8)]]
    let pb = FakePasteboard(initial: original)

    let snapshot = PasteboardManager.snapshot(pb)
    let afterWrite = PasteboardManager.writeTransient("staged", into: pb)
    let restored = PasteboardManager.restoreIfUnchanged(
      snapshot, into: pb, expectedChangeCount: afterWrite)

    XCTAssertTrue(restored)
    XCTAssertEqual(pb.readItems(), original)
  }

  func testDoesNotRestoreWhenUserCopiedSomethingElse() {
    let pb = FakePasteboard(initial: [["public.utf8-plain-text": Data("original".utf8)]])

    let snapshot = PasteboardManager.snapshot(pb)
    let afterWrite = PasteboardManager.writeTransient("staged", into: pb)
    // User copies new content before our restore fires.
    pb.externalCopy("user copied this")

    let restored = PasteboardManager.restoreIfUnchanged(
      snapshot, into: pb, expectedChangeCount: afterWrite)

    XCTAssertFalse(restored)
    XCTAssertEqual(pb.readItems(), [["public.utf8-plain-text": Data("user copied this".utf8)]])
  }

  func testRestoreEmptySnapshotJustClears() {
    let pb = FakePasteboard(initial: [])
    let snapshot = PasteboardManager.snapshot(pb)
    let afterWrite = PasteboardManager.writeTransient("staged", into: pb)
    let restored = PasteboardManager.restoreIfUnchanged(
      snapshot, into: pb, expectedChangeCount: afterWrite)
    XCTAssertTrue(restored)
    XCTAssertTrue(pb.readItems().isEmpty)
  }
}
