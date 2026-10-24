import XCTest

@testable import RbNativeCore

final class SilenceDetectorTests: XCTestCase {
  private let sampleRate = 16_000

  /// Builds `durationMs` of a loud 220 Hz tone (speech stand-in).
  private func tone(ms: Int, amplitude: Float = 0.5) -> [Float] {
    let n = sampleRate * ms / 1000
    var out = [Float](repeating: 0, count: n)
    for i in 0..<n {
      out[i] = amplitude * sinf(2 * .pi * 220 * Float(i) / Float(sampleRate))
    }
    return out
  }

  /// Builds `durationMs` of near-silence (a faint noise floor).
  private func silence(ms: Int, floor: Float = 0.001) -> [Float] {
    let n = sampleRate * ms / 1000
    var seed: UInt64 = 0x9E3779B9
    return (0..<n).map { _ in
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      let r = Float(Int32(truncatingIfNeeded: seed >> 33)) / Float(Int32.max)
      return r * floor
    }
  }

  func testDetectsASingleLongSilenceRun() {
    // speech | 3 s silence | speech
    let samples = tone(ms: 1000) + silence(ms: 3000) + tone(ms: 1000)
    let intervals = SilenceDetector.detect(
      samples: samples, sampleRate: sampleRate, minSilenceMs: 2000)

    XCTAssertEqual(intervals.count, 1)
    let run = intervals[0]
    // The run should sit between ~1 s and ~4 s (allow a window of slack).
    XCTAssertEqual(Double(run.startMs), 1000, accuracy: 120)
    XCTAssertEqual(Double(run.endMs), 4000, accuracy: 120)
    XCTAssertGreaterThanOrEqual(run.durationMs, 2000)
  }

  func testIgnoresSilenceShorterThanMinimum() {
    // A 1 s gap must be ignored when minSilence is 2 s.
    let samples = tone(ms: 1000) + silence(ms: 1000) + tone(ms: 1000)
    let intervals = SilenceDetector.detect(
      samples: samples, sampleRate: sampleRate, minSilenceMs: 2000)
    XCTAssertTrue(intervals.isEmpty)
  }

  func testDetectsMultipleRuns() {
    let samples =
      tone(ms: 500) + silence(ms: 2500) + tone(ms: 500) + silence(ms: 2500)
      + tone(ms: 500)
    let intervals = SilenceDetector.detect(
      samples: samples, sampleRate: sampleRate, minSilenceMs: 2000)
    XCTAssertEqual(intervals.count, 2)
    XCTAssertLessThan(intervals[0].endMs, intervals[1].startMs)
  }

  func testAllSpeechYieldsNoSilence() {
    let intervals = SilenceDetector.detect(
      samples: tone(ms: 3000), sampleRate: sampleRate, minSilenceMs: 1000)
    XCTAssertTrue(intervals.isEmpty)
  }

  func testEmptyInputIsSafe() {
    XCTAssertTrue(SilenceDetector.detect(samples: [], minSilenceMs: 1000).isEmpty)
  }

  func testRoundTripsThroughSyntheticWav() throws {
    // Encode a synthetic WAV, decode it back and run the detector — exercises
    // the WavPCM reader the native detectSilences uses.
    let samples = tone(ms: 1000) + silence(ms: 3000) + tone(ms: 1000)
    let wav = WavPCM.encodeMono16(samples, sampleRate: sampleRate)
    let decoded = try WavPCM.decodeMonoFloat(wav)
    XCTAssertEqual(decoded.format.sampleRate, sampleRate)
    XCTAssertEqual(decoded.format.channels, 1)

    let intervals = SilenceDetector.detect(
      samples: decoded.samples, sampleRate: decoded.format.sampleRate,
      minSilenceMs: 2000)
    XCTAssertEqual(intervals.count, 1)
  }

  func testPercentileInterpolates() {
    let v = [0.0, 1.0, 2.0, 3.0, 4.0]
    XCTAssertEqual(SilenceDetector.percentile(v, 0), 0, accuracy: 1e-9)
    XCTAssertEqual(SilenceDetector.percentile(v, 1), 4, accuracy: 1e-9)
    XCTAssertEqual(SilenceDetector.percentile(v, 0.5), 2, accuracy: 1e-9)
    XCTAssertEqual(SilenceDetector.percentile(v, 0.25), 1, accuracy: 1e-9)
  }

  func testDecodeRejectsNonWav() {
    XCTAssertThrowsError(try WavPCM.decodeMonoFloat(Data([0, 1, 2, 3])))
  }
}
