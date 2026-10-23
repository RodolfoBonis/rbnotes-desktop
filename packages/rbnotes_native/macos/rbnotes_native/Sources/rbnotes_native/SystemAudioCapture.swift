import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Captures system audio via ScreenCaptureKit (`SCStream`, audio only).
///
/// A tiny video stream is configured because `SCStream` requires one, but its
/// frames are discarded. Audio is converted to 16 kHz mono s16le. If the
/// stream cannot be created/started the caller treats the recording as
/// mic-only (`systemWavPath == null`).
@available(macOS 13.0, *)
final class SystemAudioCapture: NSObject, SCStreamDelegate, SCStreamOutput {
  private var stream: SCStream?
  private var converter: PCMConverter?
  private let audioQueue = DispatchQueue(label: "br.com.rodolfodebonis.rbnotes.scaudio")
  private let lock = NSLock()
  private var paused = false

  var onData: ((Data) -> Void)?
  var onLevel: ((Double) -> Void)?

  func start() async throws {
    let content: SCShareableContent
    do {
      content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)
    } catch {
      throw RbNativeError.systemAudioUnavailable(
        "SCShareableContent failed: \(error.localizedDescription)")
    }
    guard let display = content.displays.first else {
      throw RbNativeError.systemAudioUnavailable("no display available for SCStream")
    }

    let filter = SCContentFilter(display: display, excludingWindows: [])
    let config = SCStreamConfiguration()
    config.capturesAudio = true
    config.excludesCurrentProcessAudio = true
    config.sampleRate = 48000
    config.channelCount = 2
    // Minimal video (required by SCStream) — frames are ignored.
    config.width = 2
    config.height = 2
    config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    config.queueDepth = 3

    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    do {
      try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
      try await stream.startCapture()
    } catch {
      throw RbNativeError.systemAudioUnavailable(
        "SCStream start failed: \(error.localizedDescription)")
    }
    self.stream = stream
    RbLog.systemAudio.info("system audio capture started")
  }

  func pause() {
    lock.lock(); paused = true; lock.unlock()
  }

  func resume() {
    lock.lock(); paused = false; lock.unlock()
  }

  func stop() async {
    guard let stream else { return }
    self.stream = nil
    try? await stream.stopCapture()
    RbLog.systemAudio.info("system audio capture stopped")
  }

  // MARK: - SCStreamOutput

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType
  ) {
    guard type == .audio else { return }
    lock.lock(); let isPaused = paused; lock.unlock()
    if isPaused { return }
    guard sampleBuffer.isValid,
      let pcm = Self.pcmBuffer(from: sampleBuffer)
    else { return }

    if converter == nil {
      converter = PCMConverter(inputFormat: pcm.format)
    }
    guard let data = converter?.convert(pcm) else { return }
    onData?(data)
    onLevel?(RMS.level(of: data))
  }

  // MARK: - SCStreamDelegate

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    RbLog.systemAudio.error("SCStream stopped with error: \(error.localizedDescription)")
  }

  // MARK: - Helpers

  private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
    else { return nil }
    let format = AVAudioFormat(streamDescription: asbd)
    let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
    guard let format, frames > 0,
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
    else { return nil }
    buffer.frameLength = frames
    let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
    return status == noErr ? buffer : nil
  }
}
