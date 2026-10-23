import AVFoundation
import Foundation

/// Target format shared by both capture sources: 16 kHz mono Int16 (s16le).
enum RbAudioFormat {
  static let sampleRate: Double = 16000
  static let channels: AVAudioChannelCount = 1

  static let target: AVAudioFormat = {
    AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: sampleRate,
      channels: channels,
      interleaved: true
    )!
  }()
}

/// Converts arbitrary input PCM buffers to the 16 kHz mono s16le target format
/// and extracts little-endian `Data` plus an RMS level (0..1).
final class PCMConverter {
  private let converter: AVAudioConverter
  private let inputFormat: AVAudioFormat

  init?(inputFormat: AVAudioFormat) {
    guard let converter = AVAudioConverter(from: inputFormat, to: RbAudioFormat.target) else {
      return nil
    }
    self.converter = converter
    self.inputFormat = inputFormat
  }

  /// Converts [buffer], returning the s16le bytes. Returns nil on failure.
  func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
    let ratio = RbAudioFormat.sampleRate / inputFormat.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
    guard
      let out = AVAudioPCMBuffer(
        pcmFormat: RbAudioFormat.target, frameCapacity: capacity)
    else { return nil }

    var consumed = false
    var error: NSError?
    let status = converter.convert(to: out, error: &error) { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return buffer
    }

    if status == .error || error != nil {
      RbLog.recording.error("PCM convert failed: \(error?.localizedDescription ?? "unknown")")
      return nil
    }
    guard out.frameLength > 0, let channel = out.int16ChannelData else { return nil }
    let count = Int(out.frameLength)
    return Data(bytes: channel[0], count: count * MemoryLayout<Int16>.size)
  }
}
