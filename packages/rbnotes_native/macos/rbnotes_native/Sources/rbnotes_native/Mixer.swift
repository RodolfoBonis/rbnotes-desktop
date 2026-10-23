import AVFoundation
import Foundation

/// Builds the stereo `.m4a` playback file from the two mono 16 kHz wavs:
/// left channel = mic, right channel = system. When there is no usable system
/// file the mic is duplicated to both channels so playback stays centered.
enum Mixer {
  /// Mixes [micWav] (+ optional [systemWav]) into a stereo `.m4a` at [output].
  ///
  /// Returns whether the system channel actually contains system audio. If
  /// [systemWav] is provided but cannot be read (or is empty), the error is
  /// swallowed into a mic-only mix and `false` is returned so the caller can
  /// report `systemWavPath == null`.
  @discardableResult
  static func mixToM4A(micWav: URL, systemWav: URL?, output: URL) throws -> Bool {
    let mic = try readSamples(micWav)

    var system: [Float]?
    var systemIncluded = false
    if let systemWav {
      do {
        let samples = try readSamples(systemWav)
        if samples.isEmpty {
          RbLog.recording.error("system wav empty; falling back to mic-only mix")
        } else {
          system = samples
          systemIncluded = true
        }
      } catch {
        RbLog.recording.error(
          "system wav unreadable, mic-only mix: \(error.localizedDescription)")
      }
    }

    let frameCount = max(mic.count, system?.count ?? 0)
    guard frameCount > 0 else {
      throw RbNativeError.notRecording("nothing to mix into \(output.lastPathComponent)")
    }

    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: RbAudioFormat.sampleRate,
      AVNumberOfChannelsKey: 2,
    ]
    try? FileManager.default.removeItem(at: output)
    let file = try AVAudioFile(forWriting: output, settings: settings)
    let format = file.processingFormat

    let chunk = 16000  // ~1s per write
    var offset = 0
    while offset < frameCount {
      let n = min(chunk, frameCount - offset)
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
        let channels = buffer.floatChannelData
      else { break }
      buffer.frameLength = AVAudioFrameCount(n)
      let left = channels[0]
      let right = channels[1]
      for i in 0..<n {
        let idx = offset + i
        let micSample = idx < mic.count ? mic[idx] : 0
        let sysSample: Float
        if let system {
          sysSample = idx < system.count ? system[idx] : 0
        } else {
          sysSample = micSample
        }
        left[i] = micSample
        right[i] = sysSample
      }
      try file.write(from: buffer)
      offset += n
    }
    RbLog.recording.info("wrote playback mix \(output.lastPathComponent, privacy: .public)")
    return systemIncluded
  }

  private static func readSamples(_ url: URL) throws -> [Float] {
    let f = try AVAudioFile(forReading: url)
    let format = f.processingFormat
    let length = AVAudioFrameCount(f.length)
    guard length > 0,
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: length)
    else { return [] }
    try f.read(into: buffer)
    guard let data = buffer.floatChannelData else { return [] }
    return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
  }
}
