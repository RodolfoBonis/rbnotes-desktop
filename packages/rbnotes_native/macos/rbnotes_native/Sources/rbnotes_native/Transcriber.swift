import Foundation

/// Runs whisper transcriptions off the main thread with per-wav progress and
/// cancellation.
final class Transcriber {
  private let queue = DispatchQueue(
    label: "br.com.rodolfodebonis.rbnotes.whisper", qos: .userInitiated)
  private let lock = NSLock()
  private var cancelled: Set<String> = []

  /// Transcribes [wavPath] using [model]. [onProgress] is invoked with 0..1.
  /// Throws `RbNativeError` (`model_missing`, `transcription_cancelled`,
  /// `transcription_failed`).
  func transcribe(
    wavPath: String,
    model: WhisperModelKind,
    language: String,
    onProgress: @escaping (Double) -> Void
  ) async throws -> [[String: Any]] {
    let modelPath = ModelManager.shared.modelURL(model).path
    guard ModelManager.shared.state(model)["downloaded"] as? Bool == true else {
      throw RbNativeError.modelMissing("model not downloaded: \(model.fileName)")
    }

    clearCancel(wavPath)

    return try await withCheckedThrowingContinuation { continuation in
      queue.async { [weak self] in
        guard let self else { return }
        do {
          if self.isCancelled(wavPath) {
            throw RbNativeError.transcriptionCancelled("cancelled before start")
          }
          let samples = try WhisperBridge.readSamples(wavPath: wavPath)
          guard !samples.isEmpty else {
            throw RbNativeError.transcriptionFailed("empty audio: \(wavPath)")
          }
          let segments = try WhisperBridge.transcribe(
            samples: samples,
            modelPath: modelPath,
            language: language,
            onProgress: onProgress,
            isCancelled: { self.isCancelled(wavPath) })

          self.clearCancel(wavPath)
          let mapped = segments.map { seg in
            ["startMs": seg.startMs, "endMs": seg.endMs, "text": seg.text] as [String: Any]
          }
          continuation.resume(returning: mapped)
        } catch {
          self.clearCancel(wavPath)
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func cancel(wavPath: String) {
    lock.lock(); cancelled.insert(wavPath); lock.unlock()
    RbLog.whisper.info("cancel requested for \(wavPath, privacy: .public)")
  }

  private func isCancelled(_ wavPath: String) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return cancelled.contains(wavPath)
  }

  private func clearCancel(_ wavPath: String) {
    lock.lock(); cancelled.remove(wavPath); lock.unlock()
  }
}
