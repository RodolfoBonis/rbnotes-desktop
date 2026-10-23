import AVFoundation
import Foundation

/// Orchestrates a single recording: mic capture (+ optional system audio),
/// two incremental wav writers, ~20 Hz level events, pause/resume and the
/// stop-time `.m4a` stereo mix.
final class RecordingSession {
  let id: String
  let startedAt: Date
  private let directory: URL
  private let captureSystemAudio: Bool

  private let micCapture = AudioCapture()
  private var systemCapture: AnyObject?  // SystemAudioCapture (macOS 13+)

  private let micWriter: WavWriter
  private var systemWriter: WavWriter?
  private(set) var systemAudioActive = false

  private let writeQueue = DispatchQueue(label: "br.com.rodolfodebonis.rbnotes.wav")
  private let levelLock = NSLock()
  private var latestMicLevel: Double = 0
  private var latestSystemLevel: Double?
  private var levelTimer: DispatchSourceTimer?
  private var paused = false

  /// Emits `["mic": Double, "system": Double?]` ~20 Hz while recording.
  var onLevels: (([String: Any]) -> Void)?

  var micWavURL: URL { directory.appendingPathComponent("\(id).mic.wav") }
  var systemWavURL: URL { directory.appendingPathComponent("\(id).system.wav") }
  var playbackURL: URL { directory.appendingPathComponent("\(id).m4a") }

  init(id: String, directory: URL, captureSystemAudio: Bool) throws {
    self.id = id
    self.directory = directory
    self.captureSystemAudio = captureSystemAudio
    self.startedAt = Date()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)
    self.micWriter = try WavWriter(url: directory.appendingPathComponent("\(id).mic.wav"))
  }

  /// Starts capture. Mic failure throws; system-audio failure is swallowed so
  /// the recording continues mic-only (`systemAudioActive == false`).
  func start() async throws {
    micCapture.onData = { [weak self] data in
      self?.writeQueue.async { try? self?.micWriter.append(data) }
    }
    micCapture.onLevel = { [weak self] level in
      self?.levelLock.lock(); self?.latestMicLevel = level; self?.levelLock.unlock()
    }
    try micCapture.start()

    if captureSystemAudio, #available(macOS 13.0, *) {
      do {
        let writer = try WavWriter(url: systemWavURL)
        let system = SystemAudioCapture()
        system.onData = { [weak self, weak writer] data in
          self?.writeQueue.async { try? writer?.append(data) }
        }
        system.onLevel = { [weak self] level in
          self?.levelLock.lock(); self?.latestSystemLevel = level; self?.levelLock.unlock()
        }
        try await system.start()
        self.systemWriter = writer
        self.systemCapture = system
        self.systemAudioActive = true
        levelLock.lock(); latestSystemLevel = 0; levelLock.unlock()
      } catch {
        RbLog.systemAudio.error(
          "system audio unavailable, continuing mic-only: \(error.localizedDescription)")
        systemAudioActive = false
        try? FileManager.default.removeItem(at: systemWavURL)
        systemWriter = nil
      }
    }

    startLevelTimer()
  }

  private func startLevelTimer() {
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    timer.schedule(deadline: .now(), repeating: .milliseconds(50))  // ~20 Hz
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      self.levelLock.lock()
      let mic = self.latestMicLevel
      let system = self.latestSystemLevel
      let isPaused = self.paused
      self.levelLock.unlock()
      if isPaused { return }
      var payload: [String: Any] = ["mic": mic]
      payload["system"] = system as Any?
      self.onLevels?(payload)
    }
    timer.resume()
    levelTimer = timer
  }

  func pause() {
    levelLock.lock(); paused = true; levelLock.unlock()
    micCapture.pause()
    if #available(macOS 13.0, *) { (systemCapture as? SystemAudioCapture)?.pause() }
  }

  func resume() {
    levelLock.lock(); paused = false; levelLock.unlock()
    micCapture.resume()
    if #available(macOS 13.0, *) { (systemCapture as? SystemAudioCapture)?.resume() }
  }

  /// Stops capture, finalizes wavs, writes the `.m4a` and returns the result
  /// map for the channel.
  func stop() async throws -> [String: Any] {
    levelTimer?.cancel()
    levelTimer = nil

    micCapture.stop()
    if #available(macOS 13.0, *) {
      await (systemCapture as? SystemAudioCapture)?.stop()
    }

    // Drain pending writes before finalizing headers.
    writeQueue.sync {}
    try micWriter.finalize()
    try systemWriter?.finalize()

    let hasSystem = systemAudioActive && systemWriter != nil
    try Mixer.mixToM4A(
      micWav: micWavURL,
      systemWav: hasSystem ? systemWavURL : nil,
      output: playbackURL)

    let duration = WavWriter.duration(at: micWavURL)
    return [
      "id": id,
      "durationMs": Int(duration * 1000),
      "micWavPath": micWavURL.path,
      "systemWavPath": hasSystem ? systemWavURL.path : nil as Any?,
      "playbackPath": playbackURL.path,
    ]
  }
}
