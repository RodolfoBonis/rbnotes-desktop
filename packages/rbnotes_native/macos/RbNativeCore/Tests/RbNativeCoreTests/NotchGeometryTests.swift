import Foundation
import XCTest

@testable import RbNativeCore

final class NotchGeometryTests: XCTestCase {
  // A 1440-wide MacBook screen whose frame sits at the origin.
  private let screen = NotchGeometry.Rect(x: 0, y: 0, width: 1440, height: 900)

  func testHasNotchRejectsTinyInsets() {
    XCTAssertFalse(NotchGeometry.hasNotch(notchHeight: 0))
    XCTAssertFalse(NotchGeometry.hasNotch(notchHeight: 4))
    XCTAssertTrue(NotchGeometry.hasNotch(notchHeight: 32))
  }

  func testPillFrameIsHorizontallyCentered() {
    let f = NotchGeometry.pillFrame(screen: screen, width: 540, height: 160)
    XCTAssertEqual(f.width, 540, accuracy: 0.001)
    XCTAssertEqual(f.midX, screen.midX, accuracy: 0.001)
    XCTAssertEqual(f.x, (1440 - 540) / 2, accuracy: 0.001)
  }

  func testPillFrameHugsTheTopEdge() {
    let f = NotchGeometry.pillFrame(screen: screen, width: 540, height: 160)
    // Top edge flush with the screen top; the frame grows downward.
    XCTAssertEqual(f.maxY, screen.maxY, accuracy: 0.001)
    XCTAssertEqual(f.y, screen.maxY - 160, accuracy: 0.001)
  }

  func testPillFrameRespectsTopInsetWhenNoNotch() {
    let f = NotchGeometry.pillFrame(screen: screen, width: 300, height: 40, topInset: 24)
    XCTAssertEqual(f.maxY, screen.maxY - 24, accuracy: 0.001)
  }

  func testPillWidthIsClampedToScreen() {
    let f = NotchGeometry.pillFrame(screen: screen, width: 2000, height: 100)
    XCTAssertEqual(f.width, screen.width, accuracy: 0.001)
    XCTAssertEqual(f.x, 0, accuracy: 0.001)
  }

  func testBirthFrameMatchesNotchBoundsOnNotchedMac() {
    let birth = NotchGeometry.birthFrame(
      screen: screen, notchWidth: 200, notchHeight: 32)
    XCTAssertEqual(birth.width, 200, accuracy: 0.001)
    XCTAssertEqual(birth.height, 32, accuracy: 0.001)
    XCTAssertEqual(birth.midX, screen.midX, accuracy: 0.001)
    XCTAssertEqual(birth.maxY, screen.maxY, accuracy: 0.001)
  }

  func testBirthFrameFallsBackToSliverWithoutNotch() {
    let birth = NotchGeometry.birthFrame(
      screen: screen, notchWidth: 0, notchHeight: 0,
      fallbackWidth: 180, collapsedHeight: 6, topInset: 24)
    XCTAssertEqual(birth.width, 180, accuracy: 0.001)
    XCTAssertEqual(birth.height, 6, accuracy: 0.001)
    XCTAssertEqual(birth.midX, screen.midX, accuracy: 0.001)
    // Drops from just under the menu bar.
    XCTAssertEqual(birth.maxY, screen.maxY - 24, accuracy: 0.001)
  }

  func testGeometryWorksForAnOffsetScreen() {
    // Secondary display positioned to the right of the primary.
    let right = NotchGeometry.Rect(x: 1440, y: 0, width: 1920, height: 1080)
    let f = NotchGeometry.pillFrame(screen: right, width: 540, height: 160)
    XCTAssertEqual(f.midX, right.midX, accuracy: 0.001)
    XCTAssertEqual(f.x, 1440 + (1920 - 540) / 2, accuracy: 0.001)
    XCTAssertEqual(f.maxY, right.maxY, accuracy: 0.001)
  }
}
