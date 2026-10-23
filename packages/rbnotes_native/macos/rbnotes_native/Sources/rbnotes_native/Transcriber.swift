import Foundation

/// Transcription priority. `high` (dictation) runs on a separate lane so it
/// never waits behind a long `normal` note transcription.
enum TranscriptionPriority: String {
  case normal
  case high

  init(wire: String?) throws {
    guard let wire else {
      self = .normal
      return
    }
    guard let value = TranscriptionPriority(rawValue: wire) else {
      throw RbNativeError.invalidArgument("unknown priority: \(wire)")
    }
    self = value
  }
}

/// A serialized transcription lane: its own queue plus a per-model whisper
/// context cache with idle eviction (~5 min). whisper contexts are not
/// thread-safe, so all access happens on `queue`.
private final class TranscriptionLane {
  let queue: DispatchQueue
  private var contexts: [String: WhisperContext] = [:]
  private var evictionTimer: DispatchSourceTimer?
  private let idleTimeout: TimeInterval = 300  // 5 minutes

  init(label: String) {
    queue = DispatchQueue(label: label, qos: .userInitiated)
  }

  /// Must be called on `queue`.
  func context(forModelPath path: String) throws -> WhisperContext {
    if let existing = contexts[path] {
      return existing
    }
    let ctx = try WhisperContext(modelPath: path)
    contexts[path] = ctx
    startEvictionTimerIfNeeded()
    return ctx
  }

  private func startEvictionTimerIfNeeded() {
    guard evictionTimer == nil else { return }
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 60, repeating: 60)
    timer.setEventHandler { [weak self] in self?.evictIdle() }
    timer.resume()
    evictionTimer = timer
  }

  /// Runs on `queue`.
  private func evictIdle() {
    let now = Date()
    for (path, ctx) in contexts where now.timeIntervalSince(ctx.lastUsed) > idleTimeout {
      contexts[path] = nil  // triggers deinit → whisper_free
    }
    if contexts.isEmpty {
      evictionTimer?.cancel()
      evictionTimer = nil
    }
  }
}

/// Runs whisper transcriptions off the main thread with per-wav progress and
/// per-job cancellation, caching model contexts and routing by priority.
final class Transcriber {
  private let normalLane = TranscriptionLane(
    label: "br.com.rodolfodebonis.rbnotes.whisper.normal")
  private let highLane = TranscriptionLane(
    label: "br.com.rodolfodebonis.rbnotes.whisper.high")

  private let lock = NSLock()
  private var nextJobId = 0
  /// wavPath → the in-flight job id, so `cancel(wavPath:)` targets the current
  /// job only (no stale global flag leaking into the next run).
  private var activeJobs: [String: Int] = [:]
  private var cancelledJobs: Set<Int> = []

  /// Transcribes [wavPath] using [model]. [onProgress] is invoked with 0..1.
  /// Throws `RbNativeError` (`model_missing`, `transcription_cancelled`,
  /// `transcription_failed`).
  func transcribe(
    wavPath: String,
    model: WhisperModelKind,
    language: String,
    priority: TranscriptionPriority,
    onProgress: @escaping (Double) -> Void
  ) async throws -> [[String: Any]] {
    let modelPath = ModelManager.shared.modelURL(model).path
    guard ModelManager.shared.state(model)["downloaded"] as? Bool == true else {
      throw RbNativeError.modelMissing("model not downloaded: \(model.fileName)")
    }

    let jobId = registerJob(wavPath: wavPath)
    let lane = priority == .high ? highLane : normalLane

    defer { finishJob(wavPath: wavPath, jobId: jobId) }

    return try await withCheckedThrowingContinuation { continuation in
      lane.queue.async { [weak self] in
        guard let self else {
          continuation.resume(
            throwing: RbNativeError.transcriptionFailed("transcriber deallocated"))
          return
        }
        do {
          if self.isCancelled(jobId) {
            throw RbNativeError.transcriptionCancelled("cancelled before start")
          }
          let samples = try WhisperBridge.readSamples(wavPath: wavPath)
          let context = try lane.context(forModelPath: modelPath)
          let segments = try context.run(
            samples: samples,
            language: language,
            onProgress: onProgress,
            isCancelled: { self.isCancelled(jobId) })

          let mapped = segments.map { seg in
            ["startMs": seg.startMs, "endMs": seg.endMs, "text": seg.text] as [String: Any]
          }
          continuation.resume(returning: mapped)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func cancel(wavPath: String) {
    lock.lock()
    if let jobId = activeJobs[wavPath] { cancelledJobs.insert(jobId) }
    lock.unlock()
    RbLog.whisper.info("cancel requested for \(wavPath, privacy: .public)")
  }

  // MARK: - Job bookkeeping

  private func registerJob(wavPath: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    nextJobId += 1
    let jobId = nextJobId
    activeJobs[wavPath] = jobId
    return jobId
  }

  private func finishJob(wavPath: String, jobId: Int) {
    lock.lock()
    if activeJobs[wavPath] == jobId { activeJobs[wavPath] = nil }
    cancelledJobs.remove(jobId)
    lock.unlock()
  }

  private func isCancelled(_ jobId: Int) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return cancelledJobs.contains(jobId)
  }
}
