import Foundation

/// Incremental WAV writer for 16 kHz mono PCM s16le.
///
/// A 44-byte canonical header is written up front with placeholder sizes;
/// samples are appended as they arrive. [finalize] patches the RIFF chunk
/// size and the `data` sub-chunk size. If the process crashes mid-recording
/// the header keeps its placeholder sizes — [repairHeader] recomputes them
/// from the on-disk file size so the orphaned file becomes playable.
final class WavWriter {
  static let sampleRate: UInt32 = 16000
  static let channels: UInt16 = 1
  static let bitsPerSample: UInt16 = 16
  static let headerSize = 44

  private let handle: FileHandle
  let url: URL
  private(set) var bytesWritten: Int = 0

  init(url: URL) throws {
    self.url = url
    FileManager.default.createFile(atPath: url.path, contents: nil)
    guard let handle = try? FileHandle(forWritingTo: url) else {
      throw RbNativeError.notRecording("cannot open wav for writing: \(url.path)")
    }
    self.handle = handle
    try handle.write(contentsOf: Self.makeHeader(dataBytes: 0))
  }

  /// Appends raw interleaved s16le bytes.
  func append(_ data: Data) throws {
    try handle.write(contentsOf: data)
    bytesWritten += data.count
  }

  /// Patches the header sizes and closes the file.
  func finalize() throws {
    try handle.seek(toOffset: 0)
    try handle.write(contentsOf: Self.makeHeader(dataBytes: bytesWritten))
    try handle.close()
  }

  /// Number of 16 kHz mono samples written so far (for duration/levels).
  var frameCount: Int { bytesWritten / 2 }

  // MARK: - Header

  static func makeHeader(dataBytes: Int) -> Data {
    let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
    let blockAlign = channels * (bitsPerSample / 8)
    let riffChunkSize = UInt32(36 + dataBytes)

    var header = Data()
    func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
    func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }

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
    append32(UInt32(dataBytes))
    return header
  }

  /// Repairs the header of an orphaned wav using its actual file size.
  /// Returns the duration of the audio data. Safe to call on already-valid
  /// files (it just rewrites the same sizes).
  @discardableResult
  static func repairHeader(at url: URL) throws -> TimeInterval {
    let handle = try FileHandle(forUpdating: url)
    defer { try? handle.close() }

    let fileSize = Int(try handle.seekToEnd())
    guard fileSize >= headerSize else {
      throw RbNativeError.notRecording("wav too small to repair: \(url.path)")
    }
    let dataBytes = fileSize - headerSize
    try handle.seek(toOffset: 0)
    try handle.write(contentsOf: makeHeader(dataBytes: dataBytes))

    let frames = dataBytes / Int(bitsPerSample / 8)
    return Double(frames) / Double(sampleRate)
  }

  /// Reads the data-byte duration of a (valid) wav without mutating it.
  static func duration(at url: URL) -> TimeInterval {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attrs[.size] as? Int, size > headerSize
    else { return 0 }
    let frames = (size - headerSize) / Int(bitsPerSample / 8)
    return Double(frames) / Double(sampleRate)
  }
}
