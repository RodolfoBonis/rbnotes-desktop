import Foundation

/// Pure reader/writer for canonical 16-bit PCM WAV files (any channel count),
/// used by `RbNative.detectSilences` and exercised with synthetic WAVs in
/// `swift test`. Foundation-only so it lives in `RbNativeCore`.
///
/// The reader is tolerant: it scans the RIFF chunk list for `fmt `/`data`
/// rather than assuming a fixed 44-byte header, and downmixes to mono.
public enum WavPCM {
  public struct Format: Equatable {
    public let sampleRate: Int
    public let channels: Int
  }

  public struct DecodeError: Error { public let reason: String }

  /// Decodes [data] into mono float samples (-1..1) plus the source format.
  public static func decodeMonoFloat(_ data: Data) throws -> (samples: [Float], format: Format) {
    let bytes = [UInt8](data)
    guard bytes.count >= 12,
      bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,  // "RIFF"
      bytes[8] == 0x57, bytes[9] == 0x41, bytes[10] == 0x56, bytes[11] == 0x45  // "WAVE"
    else {
      throw DecodeError(reason: "not a RIFF/WAVE file")
    }

    var channels = 0
    var sampleRate = 0
    var bitsPerSample = 0
    var pcm: [UInt8] = []

    var offset = 12
    while offset + 8 <= bytes.count {
      let id = String(bytes: bytes[offset..<offset + 4], encoding: .ascii) ?? ""
      let size = Int(readU32LE(bytes, offset + 4))
      let bodyStart = offset + 8
      let bodyEnd = min(bytes.count, bodyStart + size)
      if id == "fmt " && bodyEnd - bodyStart >= 16 {
        channels = Int(readU16LE(bytes, bodyStart + 2))
        sampleRate = Int(readU32LE(bytes, bodyStart + 4))
        bitsPerSample = Int(readU16LE(bytes, bodyStart + 14))
      } else if id == "data" {
        pcm = Array(bytes[bodyStart..<bodyEnd])
      }
      // Chunks are word-aligned (padded to even sizes).
      offset = bodyStart + size + (size % 2)
    }

    guard channels > 0, sampleRate > 0 else {
      throw DecodeError(reason: "missing/invalid fmt chunk")
    }
    guard bitsPerSample == 16 else {
      throw DecodeError(reason: "unsupported bits-per-sample: \(bitsPerSample)")
    }

    let frameBytes = 2 * channels
    let frames = pcm.count / frameBytes
    var mono = [Float](repeating: 0, count: frames)
    pcm.withUnsafeBytes { raw in
      let s16 = raw.bindMemory(to: Int16.self)
      for f in 0..<frames {
        var acc = 0.0
        for c in 0..<channels {
          acc += Double(Int16(littleEndian: s16[f * channels + c])) / 32_768.0
        }
        mono[f] = Float(acc / Double(channels))
      }
    }
    return (mono, Format(sampleRate: sampleRate, channels: channels))
  }

  /// Encodes mono float samples (-1..1) as a 16-bit PCM WAV. Used by tests to
  /// synthesize fixtures.
  public static func encodeMono16(_ samples: [Float], sampleRate: Int = 16_000) -> Data {
    var pcm = Data(capacity: samples.count * 2)
    for s in samples {
      let clamped = max(-1, min(1, s))
      let v = Int16(clamped * 32_767)
      withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
    }
    var out = Data()
    func a32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
    func a16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
    let byteRate = UInt32(sampleRate) * 1 * 2
    out.append(contentsOf: Array("RIFF".utf8))
    a32(UInt32(36 + pcm.count))
    out.append(contentsOf: Array("WAVE".utf8))
    out.append(contentsOf: Array("fmt ".utf8))
    a32(16)
    a16(1)  // PCM
    a16(1)  // mono
    a32(UInt32(sampleRate))
    a32(byteRate)
    a16(2)  // block align
    a16(16)  // bits per sample
    out.append(contentsOf: Array("data".utf8))
    a32(UInt32(pcm.count))
    out.append(pcm)
    return out
  }

  private static func readU32LE(_ b: [UInt8], _ i: Int) -> UInt32 {
    UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
  }
  private static func readU16LE(_ b: [UInt8], _ i: Int) -> UInt16 {
    UInt16(b[i]) | UInt16(b[i + 1]) << 8
  }
}
