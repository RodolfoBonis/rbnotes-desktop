import Foundation

/// In-recording ("live") transcription using the tiny whisper model.
///
/// Buffers mic (and, if captured, system) 16 kHz mono s16le samples and, every
/// ~4 s of new audio, transcribes the most recent ~5 s window (so consecutive
/// windows overlap by ~1 s) on a low-priority `.utility` lane that is separate
/// from the main `Transcriber`. The overlap is de-duplicated textually by
/// `LiveTranscriptAccumulator`, and the accumulated transcript is emitted via
/// [emit].
///
/// Design constraints:
/// - `appendMic`/`appendSystem` only copy bytes under a short lock, so they
///   never delay the caller (the wav-writer queue).
/// - At most one window is transcribed at a time; if a new window becomes due
///   while one is still running it is dropped (we never let the lane back up).
/// - The tiny model is downloaded automatically if missing; until it is ready
///   (or if loading fails) no windows are transcribed and recording is
///   unaffected.
final class LiveTranscriber {
  /// Emits `(accumulated text, isFinal)`. Called on the live lane.
  typealias Emit = (String, Bool) -> Void

  private let language: String
  private let emit: Emit

  private let lane = DispatchQueue(
    label: "br.com.rodolfodebonis.rbnotes.whisper.live", qos: .utility)
  private let lock = NSLock()

  // Shared mutable state (guarded by `lock`).
  private var micBuffer: [Int16] = []
  private var systemBuffer: [Int16] = []
  private var pendingHopSamples = 0
  private var transcribing = false
  private var modelReady = false
  private var paused = false
  private var stopped = false

  // Lane-only state.
  private var context: WhisperContext?
  private var accumulator = LiveTranscriptAccumulator()
  private var lastEmittedText = ""

  private let sampleRate = 16_000
  private let windowSamples = 16_000 * 5  // 5 s window
  private let hopSamples = 16_000 * 4  // advance 4 s → 1 s overlap

  init(language: String, emit: @escaping Emit) {
    self.language = language
    self.emit = emit
  }

  /// Ensures the tiny model is available (downloading in the background if
  /// needed) and loads the whisper context on the lane.
  func start() {
    let kind = WhisperModelKind.tiny
    if ModelManager.shared.state(kind)["downloaded"] as? Bool == true {
      lane.async { [weak self] in self?.loadContext() }
      return
    }
    RbLog.whisper.info("live: tiny model missing, downloading in background")
    ModelManager.shared.download(
      kind, progress: { _ in },
      completion: { [weak self] result in
        guard let self else { return }
        if case .success = result {
          self.lane.async { self.loadContext() }
        } else {
          RbLog.whisper.error("live: tiny model download failed; live transcription disabled")
        }
      })
  }

  /// Runs on the lane.
  private func loadContext() {
    guard context == nil else {
      lock.lock(); modelReady = true; lock.unlock()
      return
    }
    do {
      context = try WhisperContext(modelPath: ModelManager.shared.modelURL(.tiny).path)
      lock.lock(); modelReady = true; lock.unlock()
      RbLog.whisper.info("live: tiny context ready")
    } catch {
      RbLog.whisper.error("live: cannot load tiny context: \(error.localizedDescription)")
    }
  }

  // MARK: - Audio input (hot path — keep cheap)

  func appendMic(_ data: Data) {
    let samples = Self.samples(from: data)
    guard !samples.isEmpty else { return }

    var fire = false
    var micWin: [Int16] = []
    var sysWin: [Int16] = []
    lock.lock()
    if !stopped && !paused {
      micBuffer.append(contentsOf: samples)
      if micBuffer.count > windowSamples {
        micBuffer.removeFirst(micBuffer.count - windowSamples)
      }
      pendingHopSamples += samples.count
      if modelReady, !transcribing, pendingHopSamples >= hopSamples,
        micBuffer.count >= hopSamples
      {
        transcribing = true
        pendingHopSamples = 0
        micWin = micBuffer
        sysWin = systemBuffer
        fire = true
      }
    }
    lock.unlock()

    if fire {
      lane.async { [weak self] in self?.process(mic: micWin, system: sysWin) }
    }
  }

  func appendSystem(_ data: Data) {
    let samples = Self.samples(from: data)
    guard !samples.isEmpty else { return }
    lock.lock()
    if !stopped && !paused {
      systemBuffer.append(contentsOf: samples)
      if systemBuffer.count > windowSamples {
        systemBuffer.removeFirst(systemBuffer.count - windowSamples)
      }
    }
    lock.unlock()
  }

  // MARK: - Lifecycle

  func pause() {
    lock.lock()
    paused = true
    lock.unlock()
  }

  func resume() {
    lock.lock()
    paused = false
    // Drop buffered audio so we do not stitch across the pause gap.
    pendingHopSamples = 0
    micBuffer.removeAll(keepingCapacity: true)
    systemBuffer.removeAll(keepingCapacity: true)
    lock.unlock()
  }

  /// Marks the recorder stopped, transcribes a final window and emits a final
  /// (`isFinal == true`) transcript. Safe to call once.
  func stop() {
    lock.lock()
    if stopped {
      lock.unlock()
      return
    }
    stopped = true
    let micWin = micBuffer
    let sysWin = systemBuffer
    lock.unlock()

    lane.async { [weak self] in
      guard let self else { return }
      if let context = self.context {
        let mixed = Self.mix(mic: micWin, system: sysWin)
        if !mixed.isEmpty, let segments = try? context.run(samples: mixed, language: self.language) {
          self.accumulator.append(segments.map(\.text).joined(separator: " "))
        }
      }
      self.emit(self.accumulator.text, true)
      self.context = nil  // free the whisper context
    }
  }

  // MARK: - Transcription (lane)

  private func process(mic: [Int16], system: [Int16]) {
    defer {
      lock.lock()
      transcribing = false
      lock.unlock()
    }
    guard let context else { return }
    let mixed = Self.mix(mic: mic, system: system)
    guard !mixed.isEmpty else { return }
    do {
      let segments = try context.run(samples: mixed, language: language)
      accumulator.append(segments.map(\.text).joined(separator: " "))
    } catch {
      RbLog.whisper.error("live: window transcription failed: \(error.localizedDescription)")
      return
    }
    let text = accumulator.text
    if text != lastEmittedText {
      lastEmittedText = text
      emit(text, false)
    }
  }

  // MARK: - Helpers

  /// Mixes mic + system mono s16le windows into normalized Float samples,
  /// aligning them at their most-recent sample (both windows are trailing).
  static func mix(mic: [Int16], system: [Int16]) -> [Float] {
    if system.isEmpty {
      return mic.map { Float($0) / 32_768.0 }
    }
    let n = mic.count
    let offset = n - system.count
    var out = [Float](repeating: 0, count: n)
    for i in 0..<n {
      var v = Float(mic[i]) / 32_768.0
      let sysIdx = i - offset
      if sysIdx >= 0, sysIdx < system.count {
        v += Float(system[sysIdx]) / 32_768.0
      }
      out[i] = max(-1.0, min(1.0, v))
    }
    return out
  }

  static func samples(from data: Data) -> [Int16] {
    let count = data.count / MemoryLayout<Int16>.size
    guard count > 0 else { return [] }
    return data.withUnsafeBytes { raw in
      Array(raw.bindMemory(to: Int16.self).prefix(count))
    }
  }
}
