import AVFoundation
import Foundation

/// Captures the microphone via `AVAudioEngine`, converts to 16 kHz mono s16le
/// and forwards the bytes + an RMS level to the owner. Supports pause/resume
/// (buffers are dropped while paused, the engine keeps running).
final class AudioCapture {
  private let engine = AVAudioEngine()
  private var converter: PCMConverter?
  private let lock = NSLock()
  private var paused = false

  /// Called on the audio thread with converted s16le bytes to persist.
  var onData: ((Data) -> Void)?
  /// Called with the latest RMS level (0..1).
  var onLevel: ((Double) -> Void)?

  private(set) var isRunning = false

  func start() throws {
    let input = engine.inputNode
    let inputFormat = input.inputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0 else {
      throw RbNativeError.notRecording("microphone input unavailable")
    }
    guard let converter = PCMConverter(inputFormat: inputFormat) else {
      throw RbNativeError.notRecording("cannot create mic audio converter")
    }
    self.converter = converter

    input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
      [weak self] buffer, _ in
      self?.process(buffer)
    }

    engine.prepare()
    do {
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      throw RbNativeError.notRecording("AVAudioEngine failed to start: \(error.localizedDescription)")
    }
    isRunning = true
    RbLog.recording.info("mic capture started @ \(inputFormat.sampleRate, privacy: .public) Hz")
  }

  private func process(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    let isPaused = paused
    lock.unlock()
    if isPaused { return }

    guard let data = converter?.convert(buffer) else { return }
    onData?(data)
    onLevel?(RMS.level(of: data))
  }

  func pause() {
    lock.lock()
    paused = true
    lock.unlock()
  }

  func resume() {
    lock.lock()
    paused = false
    lock.unlock()
  }

  func stop() {
    guard isRunning else { return }
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    isRunning = false
    RbLog.recording.info("mic capture stopped")
  }
}
