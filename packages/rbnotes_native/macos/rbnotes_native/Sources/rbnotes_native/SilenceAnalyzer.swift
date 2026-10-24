import AVFoundation
import Foundation

/// Native glue for `RbNative.detectSilences`: reads a wav into mono float
/// samples (at its own sample rate) and runs the pure `SilenceDetector`
/// (unit-tested in `RbNativeCore`). Kept out of the pure core because it uses
/// AVFoundation to decode the file.
enum SilenceAnalyzer {
  /// Detects silence runs longer than [minSilenceMs] in the wav at [wavPath].
  /// Throws `invalid_argument` if the file is missing/unreadable.
  static func detect(wavPath: String, minSilenceMs: Int) throws -> [[String: Any]] {
    guard FileManager.default.fileExists(atPath: wavPath) else {
      throw RbNativeError.invalidArgument("audio file not found: \(wavPath)")
    }
    let (samples, sampleRate) = try read(wavPath: wavPath)
    let intervals = SilenceDetector.detect(
      samples: samples, sampleRate: sampleRate, minSilenceMs: max(0, minSilenceMs))
    return intervals.map { ["startMs": $0.startMs, "endMs": $0.endMs] }
  }

  /// Reads [wavPath] into mono float samples plus the source sample rate.
  private static func read(wavPath: String) throws -> ([Float], Int) {
    let url = URL(fileURLWithPath: wavPath)
    do {
      let file = try AVAudioFile(forReading: url)
      let format = file.processingFormat
      let length = AVAudioFrameCount(file.length)
      guard length > 0,
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: length)
      else { return ([], Int(format.sampleRate)) }
      try file.read(into: buffer)
      guard let channel = buffer.floatChannelData else { return ([], Int(format.sampleRate)) }
      let channelCount = Int(format.channelCount)
      let frames = Int(buffer.frameLength)
      var mono = [Float](repeating: 0, count: frames)
      if channelCount == 1 {
        mono = Array(UnsafeBufferPointer(start: channel[0], count: frames))
      } else {
        for c in 0..<channelCount {
          let data = channel[c]
          for f in 0..<frames { mono[f] += data[f] / Float(channelCount) }
        }
      }
      return (mono, Int(format.sampleRate))
    } catch {
      throw RbNativeError.invalidArgument("cannot read wav: \(error.localizedDescription)")
    }
  }
}
