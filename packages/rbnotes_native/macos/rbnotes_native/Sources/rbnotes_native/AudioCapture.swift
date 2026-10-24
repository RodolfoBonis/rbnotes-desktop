import AVFoundation
import CoreAudio
import Foundation
import QuartzCore

/// Captures the microphone via `AVAudioEngine`, converts to 16 kHz mono s16le
/// and forwards the bytes + an RMS level to the owner. Supports pause/resume
/// (buffers are dropped while paused, the engine keeps running) and recovers
/// from `AVAudioEngineConfigurationChange` (e.g. default device swap) by
/// reinstalling the tap and restarting the engine while keeping the same
/// `onData` sink (and therefore the same wav writer).
///
/// An optional explicit input device (`AudioDeviceID`) can be selected; it is
/// re-applied across configuration-change restarts.
final class AudioCapture {
  private let engine = AVAudioEngine()
  private var converter: PCMConverter?
  private let lock = NSLock()
  private var paused = false
  private var _isRunning = false
  private var _firstBufferHostTime: Double?
  private var configObserver: NSObjectProtocol?
  private var inputDeviceId: AudioDeviceID?
  private var noiseReduction = false

  /// Called on the audio thread with converted s16le bytes to persist.
  var onData: ((Data) -> Void)?
  /// Called with the latest RMS level (0..1).
  var onLevel: ((Double) -> Void)?
  /// Called with a diagnostic when an asynchronous failure/recovery occurs.
  var onError: ((NativeDiagnostic) -> Void)?

  var isRunning: Bool {
    lock.lock(); defer { lock.unlock() }
    return _isRunning
  }

  /// Monotonic host time (`CACurrentMediaTime`) of the first captured buffer,
  /// for mic/system alignment. Nil until the first buffer arrives.
  var firstBufferHostTime: Double? {
    lock.lock(); defer { lock.unlock() }
    return _firstBufferHostTime
  }

  /// Starts capture, optionally on an explicit [deviceId] (nil = system
  /// default input).
  func start(deviceId: AudioDeviceID? = nil, noiseReduction: Bool = false) throws {
    inputDeviceId = deviceId
    self.noiseReduction = noiseReduction
    try startEngine()
    observeConfigurationChanges()
  }

  private func startEngine() throws {
    let input = engine.inputNode
    applyInputDeviceIfNeeded(input)
    applyNoiseReductionIfNeeded(input)
    // Voice processing changes the input node's format (sample rate and channel
    // count), so the format must be read AFTER enabling it and the converter
    // built from the resulting format.
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
      throw RbNativeError.notRecording(
        "AVAudioEngine failed to start: \(error.localizedDescription)")
    }
    lock.lock(); _isRunning = true; lock.unlock()
    RbLog.recording.info("mic capture started @ \(inputFormat.sampleRate, privacy: .public) Hz")
  }

  /// Points the engine's input node at the chosen device. Falls back to the
  /// system default (logging a diagnostic) if the device cannot be selected, so
  /// a missing/unplugged device never aborts the recording.
  private func applyInputDeviceIfNeeded(_ input: AVAudioInputNode) {
    guard let inputDeviceId else { return }
    do {
      try input.auAudioUnit.setDeviceID(inputDeviceId)
    } catch {
      RbLog.recording.error(
        "could not select input device \(inputDeviceId): \(error.localizedDescription)")
      onError?(
        NativeDiagnostic(
          DiagnosticCode.audioConfigChanged,
          "selected microphone unavailable; using the default input"))
    }
  }

  /// Enables Apple's voice processing (noise + echo cancellation) on the input
  /// node when requested. Voice processing must be toggled while the engine is
  /// stopped and it alters the node's output format; callers read the format
  /// afterwards. On failure it degrades to raw capture and emits a diagnostic —
  /// it never aborts the recording, and it does not touch system-audio capture
  /// or live transcription (both consume the converted 16 kHz mono stream).
  private func applyNoiseReductionIfNeeded(_ input: AVAudioInputNode) {
    guard noiseReduction else { return }
    do {
      try input.setVoiceProcessingEnabled(true)
      RbLog.recording.info("voice processing (noise reduction) enabled")
    } catch {
      RbLog.recording.error(
        "voice processing could not be enabled: \(error.localizedDescription)")
      onError?(
        NativeDiagnostic(
          DiagnosticCode.noiseReductionUnavailable,
          "redução de ruído indisponível; gravando sem ela: \(error.localizedDescription)"))
    }
  }

  /// Reinstalls the tap and restarts the engine after a device/route change.
  private func observeConfigurationChanges() {
    configObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
    ) { [weak self] _ in
      self?.handleConfigurationChange()
    }
  }

  private func handleConfigurationChange() {
    lock.lock()
    let running = _isRunning
    lock.unlock()
    guard running else { return }

    RbLog.recording.notice("AVAudioEngine configuration changed — restarting mic engine")
    onError?(
      NativeDiagnostic(
        DiagnosticCode.audioConfigChanged,
        "microphone audio configuration changed; restarting capture"))

    let input = engine.inputNode
    input.removeTap(onBus: 0)
    engine.stop()
    do {
      try startEngine()
    } catch {
      lock.lock(); _isRunning = false; lock.unlock()
      RbLog.recording.error("mic engine restart failed: \(error.localizedDescription)")
      onError?(
        NativeDiagnostic(
          DiagnosticCode.audioEngineRestartFailed,
          "microphone capture could not be restarted: \(error.localizedDescription)"))
    }
  }

  private func process(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    let isPaused = paused
    lock.unlock()
    if isPaused { return }

    guard let data = converter?.convert(buffer) else { return }
    lock.lock()
    if _firstBufferHostTime == nil { _firstBufferHostTime = CACurrentMediaTime() }
    lock.unlock()
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
    lock.lock()
    guard _isRunning else { lock.unlock(); return }
    _isRunning = false
    lock.unlock()

    if let configObserver {
      NotificationCenter.default.removeObserver(configObserver)
      self.configObserver = nil
    }
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    RbLog.recording.info("mic capture stopped")
  }
}
