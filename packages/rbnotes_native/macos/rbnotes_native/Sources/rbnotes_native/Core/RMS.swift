import Foundation

/// Root-mean-square level helper for interleaved s16le PCM bytes.
///
/// Pure (Foundation only) so it can be unit-tested via `RbNativeCore`.
public enum RMS {
  /// Root-mean-square level (0..1) of interleaved s16le bytes, with a light
  /// perceptual boost so quiet speech still registers on a meter. Returns 0
  /// for empty or odd-sized (sub-sample) buffers.
  public static func level(of data: Data) -> Double {
    guard data.count >= MemoryLayout<Int16>.size else { return 0 }
    return data.withUnsafeBytes { raw -> Double in
      let samples = raw.bindMemory(to: Int16.self)
      guard !samples.isEmpty else { return 0 }
      var sum = 0.0
      for sample in samples {
        let normalized = Double(sample) / 32_768.0
        sum += normalized * normalized
      }
      let rms = (sum / Double(samples.count)).squareRoot()
      return min(1.0, rms * 1.8)
    }
  }
}
