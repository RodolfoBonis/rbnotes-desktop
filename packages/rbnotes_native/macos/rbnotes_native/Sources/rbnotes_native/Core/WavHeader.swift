import Foundation

/// Pure, Flutter-independent WAV header logic for 16 kHz mono PCM s16le files.
///
/// Extracted from `WavWriter` so it can be unit-tested with `swift test` via
/// the `RbNativeCore` auxiliary package. Handles truncated (odd-sized) files
/// by rounding the `data` chunk down to a whole sample frame, keeping the file
/// valid and playable.
public enum WavHeader {
  public static let sampleRate: UInt32 = 16_000
  public static let channels: UInt16 = 1
  public static let bitsPerSample: UInt16 = 16
  public static let headerSize = 44
  public static let bytesPerFrame = Int(bitsPerSample / 8) * Int(channels)

  /// Error thrown by [repair] when the on-disk file is smaller than a header.
  public struct FileTooSmall: Error { public let path: String }

  /// Builds a 44-byte canonical header. [dataBytes] is rounded down to a whole
  /// frame so a truncated last sample never produces an invalid chunk size.
  public static func make(dataBytes: Int) -> Data {
    let usableBytes = max(0, dataBytes - (dataBytes % bytesPerFrame))
    let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
    let blockAlign = channels * (bitsPerSample / 8)
    let riffChunkSize = UInt32(36 + usableBytes)

    var header = Data()
    func append32(_ value: UInt32) {
      withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
    }
    func append16(_ value: UInt16) {
      withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
    }

    header.append(contentsOf: Array("RIFF".utf8))
    append32(riffChunkSize)
    header.append(contentsOf: Array("WAVE".utf8))
    header.append(contentsOf: Array("fmt ".utf8))
    append32(16)  // PCM fmt chunk size
    append16(1)  // audio format = PCM
    append16(channels)
    append32(sampleRate)
    append32(byteRate)
    append16(blockAlign)
    append16(bitsPerSample)
    header.append(contentsOf: Array("data".utf8))
    append32(UInt32(usableBytes))
    return header
  }

  /// Duration (seconds) of `dataBytes` of audio, rounded down to whole frames.
  public static func duration(dataBytes: Int) -> TimeInterval {
    let frames = max(0, dataBytes) / bytesPerFrame
    return Double(frames) / Double(sampleRate)
  }

  /// Repairs the header of an orphaned/truncated wav using its actual file
  /// size and returns the audio duration. Safe to call on already-valid files.
  @discardableResult
  public static func repair(at url: URL) throws -> TimeInterval {
    let handle = try FileHandle(forUpdating: url)
    defer { try? handle.close() }

    let fileSize = Int(try handle.seekToEnd())
    guard fileSize >= headerSize else {
      throw FileTooSmall(path: url.path)
    }
    let dataBytes = fileSize - headerSize
    try handle.seek(toOffset: 0)
    try handle.write(contentsOf: make(dataBytes: dataBytes))
    return duration(dataBytes: dataBytes)
  }
}
