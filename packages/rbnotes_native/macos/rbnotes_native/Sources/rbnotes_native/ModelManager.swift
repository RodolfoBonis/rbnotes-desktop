import Foundation

/// Whisper models supported by the plugin, matching the Dart `WhisperModel`
/// enum wire names.
enum WhisperModelKind: String {
  case largeV3TurboQ5
  case smallQ5

  init(wire: String) throws {
    guard let value = WhisperModelKind(rawValue: wire) else {
      throw RbNativeError.modelMissing("unknown model: \(wire)")
    }
    self = value
  }

  var fileName: String {
    switch self {
    case .largeV3TurboQ5: return "ggml-large-v3-turbo-q5_0.bin"
    case .smallQ5: return "ggml-small-q5_1.bin"
    }
  }

  var downloadURL: URL {
    URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
  }
}

/// Manages on-disk whisper models under
/// `~/Library/Application Support/RbNotes/models/` with atomic, resumable-safe
/// downloads (`.part` → rename) and progress reporting.
final class ModelManager: NSObject, URLSessionDownloadDelegate {
  static let shared = ModelManager()

  static var modelsDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("RbNotes/models", isDirectory: true)
  }

  func modelURL(_ model: WhisperModelKind) -> URL {
    Self.modelsDirectory.appendingPathComponent(model.fileName)
  }

  func state(_ model: WhisperModelKind) -> [String: Any] {
    let url = modelURL(model)
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    let size = attrs?[.size] as? Int
    let downloaded = FileManager.default.fileExists(atPath: url.path) && (size ?? 0) > 0
    return ["downloaded": downloaded, "sizeBytes": downloaded ? (size as Any?) : nil as Any?]
  }

  // MARK: - Download

  private var onProgress: ((Double) -> Void)?
  private var onComplete: ((Result<Void, Error>) -> Void)?
  private var destination: URL?
  private var expectedBytes: Int64 = 0
  private var session: URLSession?

  /// Downloads [model]. Emits progress 0..1 via [progress]; calls [completion]
  /// when finished. Only one download at a time (sufficient for the app).
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
    if FileManager.default.fileExists(atPath: finalURL.path),
      let size = (try? FileManager.default.attributesOfItem(atPath: finalURL.path))?[.size]
        as? Int, size > 0
    {
      progress(1.0)
      completion(.success(()))
      return
    }

    self.onProgress = progress
    self.onComplete = completion
    self.destination = finalURL

    let config = URLSessionConfiguration.default
    let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    self.session = session
    RbLog.whisper.info("downloading model \(model.fileName, privacy: .public)")
    session.downloadTask(with: model.downloadURL).resume()
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    expectedBytes = totalBytesExpectedToWrite
    guard totalBytesExpectedToWrite > 0 else { return }
    let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    onProgress?(min(0.999, fraction))
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let destination else { return }
    let fm = FileManager.default
    let partURL = destination.appendingPathExtension("part")
    do {
      // Validate HTTP status and size.
      if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
        throw RbNativeError.modelDownloadFailed("HTTP \(http.statusCode)")
      }
      let downloadedSize = (try fm.attributesOfItem(atPath: location.path)[.size] as? Int) ?? 0
      if expectedBytes > 0 && Int64(downloadedSize) < expectedBytes {
        throw RbNativeError.modelDownloadFailed(
          "incomplete download (\(downloadedSize)/\(expectedBytes) bytes)")
      }
      if downloadedSize < 1_000_000 {
        throw RbNativeError.modelDownloadFailed("file too small (\(downloadedSize) bytes)")
      }

      try? fm.removeItem(at: partURL)
      try fm.moveItem(at: location, to: partURL)  // atomic staging
      try? fm.removeItem(at: destination)
      try fm.moveItem(at: partURL, to: destination)  // atomic publish

      onProgress?(1.0)
      finish(.success(()))
    } catch {
      try? fm.removeItem(at: partURL)
      finish(.failure(FlutterSafe(error)))
    }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
  ) {
    if let error {
      finish(.failure(RbNativeError.modelDownloadFailed(error.localizedDescription)))
    }
  }

  private func finish(_ result: Result<Void, Error>) {
    let completion = onComplete
    onComplete = nil
    onProgress = nil
    destination = nil
    expectedBytes = 0
    session?.finishTasksAndInvalidate()
    session = nil
    completion?(result)
  }

  private func FlutterSafe(_ error: Error) -> Error {
    if error is RbNativeError { return error }
    return RbNativeError.modelDownloadFailed(error.localizedDescription)
  }
}
