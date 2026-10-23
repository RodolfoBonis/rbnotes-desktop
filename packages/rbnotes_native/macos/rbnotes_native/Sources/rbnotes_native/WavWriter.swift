import Foundation

/// Incremental WAV writer for 16 kHz mono PCM s16le.
///
/// A 44-byte canonical header is written up front with placeholder sizes;
/// samples are appended as they arrive. [finalize] patches the RIFF chunk
/// size and the `data` sub-chunk size. If the process crashes mid-recording
/// the header keeps its placeholder sizes — [repairHeader] recomputes them
/// from the on-disk file size so the orphaned file becomes playable.
///
/// The pure header math lives in `WavHeader` (unit-tested via `RbNativeCore`).
final class WavWriter {
  static let sampleRate = WavHeader.sampleRate
  static let channels = WavHeader.channels
  static let bitsPerSample = WavHeader.bitsPerSample
  static let headerSize = WavHeader.headerSize

  private let handle: FileHandle
  let url: URL
  private(set) var bytesWritten: Int = 0
  /// Number of append calls that failed to write (surfaced as diagnostics).
  private(set) var writeFailures: Int = 0

  init(url: URL) throws {
    self.url = url
    FileManager.default.createFile(atPath: url.path, contents: nil)
    guard let handle = try? FileHandle(forWritingTo: url) else {
      throw RbNativeError.notRecording("cannot open wav for writing: \(url.path)")
    }
    self.handle = handle
    try handle.write(contentsOf: WavHeader.make(dataBytes: 0))
  }

  /// Appends raw interleaved s16le bytes. Throws on write failure so the caller
  /// can count/log/emit a diagnostic instead of silently dropping audio.
  func append(_ data: Data) throws {
    do {
      try handle.write(contentsOf: data)
      bytesWritten += data.count
    } catch {
      writeFailures += 1
      throw error
    }
  }

  /// Patches the header sizes and closes the file.
  func finalize() throws {
    try handle.seek(toOffset: 0)
    try handle.write(contentsOf: WavHeader.make(dataBytes: bytesWritten))
    try handle.close()
  }

  /// Number of 16 kHz mono samples written so far (for duration/levels).
  var frameCount: Int { bytesWritten / Int(Self.bitsPerSample / 8) }

  // MARK: - Header (delegates to the pure `WavHeader`)

  static func makeHeader(dataBytes: Int) -> Data { WavHeader.make(dataBytes: dataBytes) }

  /// Repairs the header of an orphaned wav using its actual file size and
  /// returns the audio duration. Safe to call on already-valid files.
  @discardableResult
  static func repairHeader(at url: URL) throws -> TimeInterval {
    do {
      return try WavHeader.repair(at: url)
    } catch let tooSmall as WavHeader.FileTooSmall {
      throw RbNativeError.notRecording("wav too small to repair: \(tooSmall.path)")
    }
  }

  /// Reads the data-byte duration of a (valid) wav without mutating it.
  static func duration(at url: URL) -> TimeInterval {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attrs[.size] as? Int, size > headerSize
    else { return 0 }
    return WavHeader.duration(dataBytes: size - headerSize)
  }

  /// Prepends [seconds] of silence to a finalized wav, rewriting its header.
  /// Used to align two sources that started at different host times. No-op for
  /// non-positive durations.
  static func prependSilence(at url: URL, seconds: Double) throws {
    guard seconds > 0 else { return }
    let frames = Int((seconds * Double(sampleRate)).rounded())
    guard frames > 0 else { return }
    let silence = Data(count: frames * Int(bitsPerSample / 8))

    let fileData = try Data(contentsOf: url)
    guard fileData.count >= headerSize else { return }
    let audio = fileData.subdata(in: headerSize..<fileData.count)

    var out = WavHeader.make(dataBytes: silence.count + audio.count)
    out.append(silence)
    out.append(audio)
    try out.write(to: url)
  }
}
