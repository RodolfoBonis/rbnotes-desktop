import AVFoundation
import Foundation

/// Computes normalized waveform peaks for the design's audio player.
enum Waveform {
  /// Returns [buckets] peak amplitudes (0..1), one per equal time bucket, for
  /// the audio file at [path] (`.wav` or `.m4a`). The file is read in chunks
  /// and down-mixed to mono; each bucket holds the max absolute sample in its
  /// range. Throws `transcription_failed` if the file cannot be opened.
  static func peaks(path: String, buckets: Int) throws -> [Double] {
    guard buckets > 0 else { return [] }
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
      throw RbNativeError.invalidArgument("audio file not found: \(path)")
    }

    let file: AVAudioFile
    do {
      file = try AVAudioFile(forReading: url)
    } catch {
      throw RbNativeError.transcriptionFailed(
        "cannot read audio: \(error.localizedDescription)")
    }

    let total = file.length
    guard total > 0 else { return [Double](repeating: 0, count: buckets) }

    let format = file.processingFormat
    let channelCount = Int(format.channelCount)
    // Split the timeline into `buckets` ranges; track the running max per bucket.
    var peaks = [Double](repeating: 0, count: buckets)
    let framesPerBucket = Double(total) / Double(buckets)

    let chunkFrames: AVAudioFrameCount = 64_000
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
      return peaks
    }

    var frameIndex: Int64 = 0
    while true {
      buffer.frameLength = 0
      do {
        try file.read(into: buffer, frameCount: chunkFrames)
      } catch {
        break
      }
      let read = Int(buffer.frameLength)
      guard read > 0 else { break }
      guard let channels = buffer.floatChannelData else { break }

      for f in 0..<read {
        var sample: Float = 0
        for c in 0..<channelCount { sample += channels[c][f] }
        let amp = Double(abs(sample / Float(max(1, channelCount))))
        let bucket = min(buckets - 1, Int(Double(frameIndex + Int64(f)) / framesPerBucket))
        if amp > peaks[bucket] { peaks[bucket] = amp }
      }
      frameIndex += Int64(read)
    }

    // Clamp to 0..1 (defensive; float PCM is already normalized).
    for i in 0..<buckets { peaks[i] = min(1.0, peaks[i]) }
    return peaks
  }
}
