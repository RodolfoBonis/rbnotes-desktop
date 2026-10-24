import Foundation

/// A detected run of silence, in milliseconds from the start of the audio.
public struct SilenceInterval: Equatable {
  public let startMs: Int
  public let endMs: Int
  public init(startMs: Int, endMs: Int) {
    self.startMs = startMs
    self.endMs = endMs
  }
  public var durationMs: Int { endMs - startMs }
}

/// Energy-based voice-activity detection used by `RbNative.detectSilences`.
///
/// Pure (Foundation only) so it can be unit-tested with `swift test` via
/// `RbNativeCore`. The algorithm:
///
/// 1. Split the mono signal into fixed windows (default 30 ms).
/// 2. Compute each window's RMS energy (0..1).
/// 3. Derive an **adaptive** threshold from the noise floor — a low percentile
///    of the window energies — so a quiet recording and a loud one are treated
///    the same. Windows below the threshold are "silent".
/// 4. Merge consecutive silent windows and keep only runs longer than
///    `minSilenceMs`.
public enum SilenceDetector {
  /// Detects silence runs longer than [minSilenceMs] in [samples] (mono,
  /// normalized to -1..1).
  ///
  /// - Parameters:
  ///   - windowMs: analysis window size (30 ms by default).
  ///   - noisePercentile: percentile (0..1) of window energies taken as the
  ///     noise floor (0.10 = 10th percentile).
  ///   - thresholdMultiplier: the silence threshold is the noise floor times
  ///     this factor (speech is well above the noise floor).
  ///   - absoluteFloor: a hard minimum threshold so a dead-silent recording
  ///     (noise floor ≈ 0) does not classify faint speech as silence.
  public static func detect(
    samples: [Float],
    sampleRate: Int = 16_000,
    windowMs: Int = 30,
    minSilenceMs: Int,
    noisePercentile: Double = 0.10,
    thresholdMultiplier: Double = 2.5,
    absoluteFloor: Double = 0.01
  ) -> [SilenceInterval] {
    guard sampleRate > 0, windowMs > 0, !samples.isEmpty else { return [] }
    let windowSamples = max(1, sampleRate * windowMs / 1000)
    let windowCount = samples.count / windowSamples
    guard windowCount > 0 else { return [] }

    var energies = [Double](repeating: 0, count: windowCount)
    for w in 0..<windowCount {
      let base = w * windowSamples
      var sum = 0.0
      for i in base..<(base + windowSamples) {
        let v = Double(samples[i])
        sum += v * v
      }
      energies[w] = (sum / Double(windowSamples)).squareRoot()
    }

    // Adaptive threshold from the dynamic range of the clip. Using only the
    // noise floor breaks on uniform audio (a clip that is all speech has its
    // "noise floor" at speech level, so noiseFloor*k would flag everything as
    // silent). We also look at a high percentile (speech level): when the range
    // is narrow the clip is uniform (all speech or all silence) and only the
    // absolute floor applies.
    let noiseFloor = percentile(energies, noisePercentile)
    let speechLevel = percentile(energies, 0.90)
    let threshold: Double
    if speechLevel <= absoluteFloor {
      // The whole clip is quiet → everything below the absolute floor is silent.
      threshold = absoluteFloor
    } else if speechLevel < noiseFloor * thresholdMultiplier + absoluteFloor {
      // Narrow dynamic range → treat as uniform (likely all speech): only the
      // absolute floor separates silence, so loud uniform audio is not silence.
      threshold = absoluteFloor
    } else {
      // Clear speech/silence contrast → a point low in the dynamic range.
      threshold = max(absoluteFloor, noiseFloor + (speechLevel - noiseFloor) * 0.15)
    }

    var intervals: [SilenceInterval] = []
    var runStart: Int?
    for w in 0..<windowCount {
      let isSilent = energies[w] < threshold
      if isSilent {
        if runStart == nil { runStart = w }
      } else if let start = runStart {
        appendIfLongEnough(
          &intervals, startWindow: start, endWindow: w,
          windowMs: windowMs, minSilenceMs: minSilenceMs)
        runStart = nil
      }
    }
    if let start = runStart {
      appendIfLongEnough(
        &intervals, startWindow: start, endWindow: windowCount,
        windowMs: windowMs, minSilenceMs: minSilenceMs)
    }
    return intervals
  }

  private static func appendIfLongEnough(
    _ intervals: inout [SilenceInterval], startWindow: Int, endWindow: Int,
    windowMs: Int, minSilenceMs: Int
  ) {
    let startMs = startWindow * windowMs
    let endMs = endWindow * windowMs
    if endMs - startMs >= minSilenceMs {
      intervals.append(SilenceInterval(startMs: startMs, endMs: endMs))
    }
  }

  /// The [p]-percentile (0..1) of [values] using linear interpolation. Returns
  /// 0 for an empty input. Does not mutate the caller's array.
  public static func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    if sorted.count == 1 { return sorted[0] }
    let clamped = min(1, max(0, p))
    let rank = clamped * Double(sorted.count - 1)
    let low = Int(rank.rounded(.down))
    let high = Int(rank.rounded(.up))
    if low == high { return sorted[low] }
    let frac = rank - Double(low)
    return sorted[low] * (1 - frac) + sorted[high] * frac
  }
}
