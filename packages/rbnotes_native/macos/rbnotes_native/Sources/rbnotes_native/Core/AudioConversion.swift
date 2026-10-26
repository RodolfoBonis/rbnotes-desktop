import AVFoundation
import Foundation
import os

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
  // Same subsystem/category as `RbLog.recording`; Core sources stay free of
  // plugin-only types so `swift test` can compile them.
  private static let log = Logger(
    subsystem: "br.com.rodolfodebonis.rbnotes", category: "recording")

  private let converter: AVAudioConverter
  private let inputFormat: AVAudioFormat
  /// Set when the input is a multichannel float layout (voice processing
  /// exposes the mic as 5–7 deinterleaved channels with the processed voice on
  /// channel 0). `AVAudioConverter` downmixes those layouts to pure zeros, so
  /// channel 0 is copied into this mono buffer format before converting.
  private let monoFormat: AVAudioFormat?

  init?(inputFormat: AVAudioFormat) {
    let monoFormat: AVAudioFormat?
    if inputFormat.channelCount > 2, inputFormat.commonFormat == .pcmFormatFloat32 {
      monoFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: inputFormat.sampleRate,
        channels: 1,
        interleaved: false)
    } else {
      monoFormat = nil
    }
    guard
      let converter = AVAudioConverter(
        from: monoFormat ?? inputFormat, to: RbAudioFormat.target)
    else {
      return nil
    }
    self.converter = converter
    self.inputFormat = inputFormat
    self.monoFormat = monoFormat
  }

  /// Copies channel 0 of a multichannel float buffer into a mono buffer.
  private func firstChannel(of buffer: AVAudioPCMBuffer, as format: AVAudioFormat)
    -> AVAudioPCMBuffer?
  {
    guard
      let source = buffer.floatChannelData,
      let mono = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
      let target = mono.floatChannelData
    else { return nil }
    mono.frameLength = buffer.frameLength
    let stride = buffer.stride
    let frames = Int(buffer.frameLength)
    if stride == 1 {
      target[0].update(from: source[0], count: frames)
    } else {
      // Interleaved: channel 0 is every `stride`-th sample.
      for frame in 0..<frames { target[0][frame] = source[0][frame * stride] }
    }
    return mono
  }

  /// Converts [buffer], returning the s16le bytes. Returns nil on failure.
  func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
    var buffer = buffer
    if let monoFormat {
      guard let mono = firstChannel(of: buffer, as: monoFormat) else { return nil }
      buffer = mono
    }
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
      PCMConverter.log.error("PCM convert failed: \(error?.localizedDescription ?? "unknown")")
      return nil
    }
    guard out.frameLength > 0, let channel = out.int16ChannelData else { return nil }
    let count = Int(out.frameLength)
    return Data(bytes: channel[0], count: count * MemoryLayout<Int16>.size)
  }
}
