import AVFoundation
import XCTest

@testable import RbNativeCore

final class PCMConverterTests: XCTestCase {
  /// Builds a deinterleaved float buffer with a 440 Hz tone on channel 0 and
  /// silence on every other channel — the shape voice processing produces.
  private func toneBuffer(channels: AVAudioChannelCount, sampleRate: Double = 48000)
    -> AVAudioPCMBuffer
  {
    let layout = AVAudioChannelLayout(
      layoutTag: kAudioChannelLayoutTag_Unknown | UInt32(channels))!
    let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, interleaved: false,
      channelLayout: layout)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
    buffer.frameLength = 4800
    let data = buffer.floatChannelData!
    for frame in 0..<Int(buffer.frameLength) {
      data[0][frame] = 0.5 * sin(2 * .pi * 440 * Float(frame) / Float(sampleRate))
      for channel in 1..<Int(channels) { data[channel][frame] = 0 }
    }
    return buffer
  }

  private func peak(_ data: Data) -> Int16 {
    data.withUnsafeBytes { raw in
      raw.bindMemory(to: Int16.self).map { $0 == .min ? .max : abs($0) }.max() ?? 0
    }
  }

  func testVoiceProcessingLayoutKeepsTheVoiceChannel() throws {
    // Regression: AVAudioConverter downmixed the 7-channel voice-processing
    // layout to pure zeros, so every recording with noise reduction was silent.
    let buffer = toneBuffer(channels: 7)
    let converter = try XCTUnwrap(PCMConverter(inputFormat: buffer.format))
    let data = try XCTUnwrap(converter.convert(buffer))
    XCTAssertGreaterThan(data.count, 0)
    XCTAssertGreaterThan(peak(data), 10_000)
  }

  func testMonoInputStillConverts() throws {
    let buffer = toneBuffer(channels: 1, sampleRate: 44100)
    let converter = try XCTUnwrap(PCMConverter(inputFormat: buffer.format))
    let data = try XCTUnwrap(converter.convert(buffer))
    XCTAssertGreaterThan(peak(data), 10_000)
  }
}
