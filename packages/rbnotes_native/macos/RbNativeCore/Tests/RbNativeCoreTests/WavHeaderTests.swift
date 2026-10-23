import Foundation
import XCTest

@testable import RbNativeCore

final class WavHeaderTests: XCTestCase {
  func testHeaderIsCanonical44Bytes() {
    let header = WavHeader.make(dataBytes: 0)
    XCTAssertEqual(header.count, 44)
    XCTAssertEqual(Array(header[0..<4]), Array("RIFF".utf8))
    XCTAssertEqual(Array(header[8..<12]), Array("WAVE".utf8))
    XCTAssertEqual(Array(header[36..<40]), Array("data".utf8))
  }

  func testHeaderEncodesSizesLittleEndian() {
    let dataBytes = 32_000  // 1s of 16kHz mono s16le
    let header = WavHeader.make(dataBytes: dataBytes)
    let riff = readUInt32(header, at: 4)
    let data = readUInt32(header, at: 40)
    let sampleRate = readUInt32(header, at: 24)
    XCTAssertEqual(riff, UInt32(36 + dataBytes))
    XCTAssertEqual(data, UInt32(dataBytes))
    XCTAssertEqual(sampleRate, 16_000)
  }

  func testOddDataSizeRoundsDownToWholeFrame() {
    // 1001 bytes => 500 whole int16 frames => 1000 usable bytes.
    let header = WavHeader.make(dataBytes: 1_001)
    XCTAssertEqual(readUInt32(header, at: 40), 1_000)
    XCTAssertEqual(readUInt32(header, at: 4), UInt32(36 + 1_000))
  }

  func testDurationRoundsDownOddBytes() {
    XCTAssertEqual(WavHeader.duration(dataBytes: 32_000), 1.0, accuracy: 1e-9)
    // 32001 bytes -> still 16000 frames -> 1.0s (odd trailing byte dropped).
    XCTAssertEqual(WavHeader.duration(dataBytes: 32_001), 1.0, accuracy: 1e-9)
  }

  func testRepairRecomputesSizesFromFile() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("rbheader-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }

    // Placeholder header (sizes 0) + 2000 bytes of audio, as if crashed.
    var file = WavHeader.make(dataBytes: 0)
    file.append(Data(repeating: 7, count: 2_000))
    try file.write(to: url)

    let duration = try WavHeader.repair(at: url)
    XCTAssertEqual(duration, 2_000.0 / 2.0 / 16_000.0, accuracy: 1e-9)

    let repaired = try Data(contentsOf: url)
    XCTAssertEqual(readUInt32(repaired, at: 40), 2_000)
    XCTAssertEqual(readUInt32(repaired, at: 4), UInt32(36 + 2_000))
  }

  func testRepairOddFileSizeIsValid() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("rbheader-odd-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }

    var file = WavHeader.make(dataBytes: 0)
    file.append(Data(repeating: 1, count: 2_001))  // odd trailing byte
    try file.write(to: url)

    _ = try WavHeader.repair(at: url)
    let repaired = try Data(contentsOf: url)
    // Odd byte dropped: data chunk = 2000, an even whole-frame count.
    XCTAssertEqual(readUInt32(repaired, at: 40), 2_000)
  }

  func testRepairThrowsOnTooSmallFile() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("rbheader-tiny-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(repeating: 0, count: 10).write(to: url)
    XCTAssertThrowsError(try WavHeader.repair(at: url)) { error in
      XCTAssertTrue(error is WavHeader.FileTooSmall)
    }
  }

  private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
    data.withUnsafeBytes { raw in
      raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
    }
  }
}
