import Foundation
import XCTest

@testable import RbNativeCore

final class RMSTests: XCTestCase {
  func testEmptyBufferIsZero() {
    XCTAssertEqual(RMS.level(of: Data()), 0)
  }

  func testSubSampleBufferIsZero() {
    XCTAssertEqual(RMS.level(of: Data([0x01])), 0)
  }

  func testSilenceIsZero() {
    let silence = Data(count: 320)  // 160 int16 zeros
    XCTAssertEqual(RMS.level(of: silence), 0)
  }

  func testFullScaleClampsToOne() {
    var samples = [Int16](repeating: 32_767, count: 100)
    let data = samples.withUnsafeBytes { Data($0) }
    XCTAssertEqual(RMS.level(of: data), 1.0, accuracy: 1e-9)
    _ = samples  // silence unused-warning
  }

  func testQuietSignalIsBetweenZeroAndOne() {
    let samples = [Int16](repeating: 1_000, count: 100)
    let data = samples.withUnsafeBytes { Data($0) }
    let level = RMS.level(of: data)
    XCTAssertGreaterThan(level, 0)
    XCTAssertLessThan(level, 1.0)
  }
}
