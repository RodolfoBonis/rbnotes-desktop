import CryptoKit
import Foundation

/// Whisper models supported by the plugin, matching the Dart `WhisperModel`
/// enum wire names. Each carries the official Hugging Face file size and
/// SHA-256 (git-LFS oid) so downloads can be verified and `modelState` can
/// require an exact size match.
enum WhisperModelKind: String {
  case largeV3TurboQ5
  case smallQ5

  init(wire: String) throws {
    guard let value = WhisperModelKind(rawValue: wire) else {
      throw RbNativeError.invalidArgument("unknown model: \(wire)")
    }
    self = value
  }

  var fileName: String {
    switch self {
    case .largeV3TurboQ5: return "ggml-large-v3-turbo-q5_0.bin"
    case .smallQ5: return "ggml-small-q5_1.bin"
    }
  }

  /// Exact file size in bytes (Hugging Face `x-linked-size`).
  var expectedSize: Int64 {
    switch self {
    case .largeV3TurboQ5: return 574_041_195
    case .smallQ5: return 190_085_487
    }
  }

  /// SHA-256 of the file (Hugging Face `x-linked-etag` / git-LFS oid).
  var expectedSHA256: String {
    switch self {
    case .largeV3TurboQ5:
      return "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
    case .smallQ5:
      return "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"
    }
  }

  var downloadURL: URL {
    URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
  }
}

/// Manages on-disk whisper models under
/// `~/Library/Application Support/RbNotes/models/` with atomic, verified
/// downloads (`.part` → SHA-256 check → rename) and progress reporting.
/// Supports concurrent downloads of *different* models, rejects a second
/// concurrent download of the *same* model, and cancels on stream teardown.
final class ModelManager: NSObject, URLSessionDownloadDelegate {
  static let shared = ModelManager()

  static var modelsDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("RbNotes/models", isDirectory: true)
  }

  func modelURL(_ model: WhisperModelKind) -> URL {
    Self.modelsDirectory.appendingPathComponent(model.fileName)
  }

  /// A model counts as downloaded only if its on-disk size matches the
  /// expected size exactly.
  func state(_ model: WhisperModelKind) -> [String: Any] {
    let url = modelURL(model)
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    let size = (attrs?[.size] as? NSNumber)?.int64Value
    let downloaded = size == model.expectedSize
    return [
      "downloaded": downloaded,
      "sizeBytes": downloaded ? (Int(size ?? 0) as Any?) : nil as Any?,
    ]
  }

  // MARK: - Download bookkeeping

  private final class DownloadJob {
    let model: WhisperModelKind
    let destination: URL
    let progress: (Double) -> Void
    let completion: (Result<Void, Error>) -> Void
    var expectedBytes: Int64 = 0
    init(
      model: WhisperModelKind, destination: URL,
      progress: @escaping (Double) -> Void,
      completion: @escaping (Result<Void, Error>) -> Void
    ) {
      self.model = model
      self.destination = destination
      self.progress = progress
      self.completion = completion
    }
  }

  private let lock = NSLock()
  private var jobs: [Int: DownloadJob] = [:]  // keyed by task identifier
  private var activeModels: [String: URLSessionDownloadTask] = [:]  // fileName → task
  private lazy var session: URLSession = URLSession(
    configuration: .default, delegate: self, delegateQueue: nil)

  /// Downloads [model]. Emits progress 0..1 via [progress]; calls [completion]
  /// when finished. Rejects a concurrent download of the same model.
  func download(
    _ model: WhisperModelKind,
    progress: @escaping (Double) -> Void,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    do {
      try FileManager.default.createDirectory(
        at: Self.modelsDirectory, withIntermediateDirectories: true)
    } catch {
      completion(.failure(RbNativeError.modelDownloadFailed(
        "cannot create models dir: \(error.localizedDescription)")))
      return
    }

    let finalURL = modelURL(model)
    if let size = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size]
      as? NSNumber)?.int64Value, size == model.expectedSize
    {
      progress(1.0)
      completion(.success(()))
      return
    }

    lock.lock()
    if activeModels[model.fileName] != nil {
      lock.unlock()
      completion(.failure(RbNativeError.modelDownloadFailed(
        "download already in progress for \(model.fileName)")))
      return
    }
    let task = session.downloadTask(with: model.downloadURL)
    let job = DownloadJob(
      model: model, destination: finalURL, progress: progress, completion: completion)
    jobs[task.taskIdentifier] = job
    activeModels[model.fileName] = task
    lock.unlock()

    RbLog.whisper.info("downloading model \(model.fileName, privacy: .public)")
    task.resume()
  }

  /// Cancels an in-flight download of [model] (wired to the stream `onCancel`).
  func cancelDownload(_ model: WhisperModelKind) {
    lock.lock()
    let task = activeModels[model.fileName]
    lock.unlock()
    task?.cancel()
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    lock.lock()
    let job = jobs[downloadTask.taskIdentifier]
    job?.expectedBytes = totalBytesExpectedToWrite
    lock.unlock()
    guard let job, totalBytesExpectedToWrite > 0 else { return }
    job.progress(min(0.999, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    lock.lock()
    let job = jobs[downloadTask.taskIdentifier]
    lock.unlock()
    guard let job else { return }

    let fm = FileManager.default
    let partURL = job.destination.appendingPathExtension("part")
    do {
      if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
        throw RbNativeError.modelDownloadFailed("HTTP \(http.statusCode)")
      }
      let downloadedSize = ((try fm.attributesOfItem(atPath: location.path)[.size])
        as? NSNumber)?.int64Value ?? 0
      guard downloadedSize == job.model.expectedSize else {
        throw RbNativeError.modelDownloadFailed(
          "size mismatch (\(downloadedSize)/\(job.model.expectedSize) bytes)")
      }
      let digest = try Self.sha256(ofFileAt: location)
      guard digest == job.model.expectedSHA256 else {
        throw RbNativeError.modelDownloadFailed("checksum mismatch for \(job.model.fileName)")
      }

      try? fm.removeItem(at: partURL)
      try fm.moveItem(at: location, to: partURL)  // atomic staging
      try? fm.removeItem(at: job.destination)
      try fm.moveItem(at: partURL, to: job.destination)  // atomic publish

      job.progress(1.0)
      finish(task: downloadTask, model: job.model, .success(()))
    } catch {
      try? fm.removeItem(at: partURL)
      finish(task: downloadTask, model: job.model, .failure(Self.wrap(error)))
    }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
  ) {
    guard let error else { return }
    let nsError = error as NSError
    lock.lock()
    let job = jobs[task.taskIdentifier]
    lock.unlock()

    RbLog.whisper.error(
      "download didCompleteWithError: \(error.localizedDescription, privacy: .public)")

    // A cancellation is a user action, not a failure to log loudly.
    let wrapped: Error =
      nsError.code == NSURLErrorCancelled
      ? RbNativeError.transcriptionCancelled("download cancelled")
      : RbNativeError.modelDownloadFailed(error.localizedDescription)

    if let job {
      finish(task: task, model: job.model, .failure(wrapped))
    }
  }

  // MARK: - Helpers

  private func finish(task: URLSessionTask, model: WhisperModelKind, _ result: Result<Void, Error>) {
    lock.lock()
    let job = jobs.removeValue(forKey: task.taskIdentifier)
    if activeModels[model.fileName]?.taskIdentifier == task.taskIdentifier {
      activeModels[model.fileName] = nil
    }
    lock.unlock()
    job?.completion(result)
  }

  private static func wrap(_ error: Error) -> Error {
    if error is RbNativeError { return error }
    return RbNativeError.modelDownloadFailed(error.localizedDescription)
  }

  /// Streams the file through SHA-256 so large models are not loaded whole.
  private static func sha256(ofFileAt url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while autoreleasepool(invoking: {
      let chunk = handle.readData(ofLength: 1 << 20)  // 1 MiB
      guard !chunk.isEmpty else { return false }
      hasher.update(data: chunk)
      return true
    }) {}
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
