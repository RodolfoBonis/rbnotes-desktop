import CryptoKit
import Foundation

/// The two ONNX models the sherpa-onnx diarization pipeline needs. Pinned to an
/// exact size + SHA-256 (HuggingFace `x-linked-size`/`x-linked-etag`), verified
/// on download — exactly like the whisper models.
enum DiarizationModelFile: CaseIterable {
  /// pyannote segmentation 3.0 (sherpa-onnx export).
  case segmentation
  /// 3dspeaker CAM++ speaker embedding (the lightest high-quality option).
  case embedding

  var fileName: String {
    switch self {
    case .segmentation: return "pyannote-segmentation-3-0.onnx"
    case .embedding: return "3dspeaker-campplus-sv-zh-cn-16k-common.onnx"
    }
  }

  var expectedSize: Int64 {
    switch self {
    case .segmentation: return 5_992_913
    case .embedding: return 28_281_138
    }
  }

  var expectedSHA256: String {
    switch self {
    case .segmentation:
      return "220ad67ca923bef2fa91f2390c786097bf305bceb5e261d4af67b38e938e1079"
    case .embedding:
      return "f682b514c05d947ee3fa91cd6ec6c5c7543479a128373fa29b1faedccd21fd11"
    }
  }

  var downloadURL: URL {
    switch self {
    case .segmentation:
      return URL(
        string:
          "https://huggingface.co/csukuangfj/sherpa-onnx-pyannote-segmentation-3-0/resolve/main/model.onnx"
      )!
    case .embedding:
      return URL(
        string:
          "https://huggingface.co/csukuangfj/speaker-embedding-models/resolve/main/3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx"
      )!
    }
  }
}

/// Manages the on-disk diarization models under
/// `~/Library/Application Support/RbNotes/models/diarization/` with atomic,
/// verified downloads and combined progress. Mirrors `ModelManager`; both
/// files are downloaded sequentially and progress is weighted by size.
final class DiarizationModelManager: NSObject, URLSessionDownloadDelegate {
  static let shared = DiarizationModelManager()

  static var modelsDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("RbNotes/models/diarization", isDirectory: true)
  }

  func path(for file: DiarizationModelFile) -> URL {
    Self.modelsDirectory.appendingPathComponent(file.fileName)
  }

  var segmentationPath: String { path(for: .segmentation).path }
  var embeddingPath: String { path(for: .embedding).path }

  /// Whether a file is present with its exact expected size.
  private func isPresent(_ file: DiarizationModelFile) -> Bool {
    let attrs = try? FileManager.default.attributesOfItem(atPath: path(for: file).path)
    return (attrs?[.size] as? NSNumber)?.int64Value == file.expectedSize
  }

  /// `{downloaded, sizeBytes?}` — downloaded only when every file matches; the
  /// size is the total on disk.
  func state() -> [String: Any] {
    let all = DiarizationModelFile.allCases
    let downloaded = all.allSatisfy(isPresent)
    let total = all.reduce(Int64(0)) { $0 + $1.expectedSize }
    return [
      "downloaded": downloaded,
      "sizeBytes": downloaded ? (Int(total) as Any?) : nil as Any?,
    ]
  }

  var isDownloaded: Bool { DiarizationModelFile.allCases.allSatisfy(isPresent) }

  // MARK: - Download (sequential, combined progress)

  private let lock = NSLock()
  private var queueRemaining: [DiarizationModelFile] = []
  private var completedBytes: Int64 = 0
  private var totalBytes: Int64 = 0
  private var currentTask: URLSessionDownloadTask?
  private var progressCb: ((Double) -> Void)?
  private var completionCb: ((Result<Void, Error>) -> Void)?
  private var cancelled = false
  private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

  /// Downloads any missing models. Emits combined progress 0..1 and calls
  /// [completion] once. Rejects a concurrent download.
  func download(
    progress: @escaping (Double) -> Void,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    lock.lock()
    if progressCb != nil {
      lock.unlock()
      completion(.failure(RbNativeError.modelDownloadFailed("diarization download already in progress")))
      return
    }
    do {
      try FileManager.default.createDirectory(
        at: Self.modelsDirectory, withIntermediateDirectories: true)
    } catch {
      lock.unlock()
      completion(.failure(RbNativeError.modelDownloadFailed(
        "cannot create diarization models dir: \(error.localizedDescription)")))
      return
    }

    let missing = DiarizationModelFile.allCases.filter { !isPresent($0) }
    if missing.isEmpty {
      lock.unlock()
      progress(1.0)
      completion(.success(()))
      return
    }
    queueRemaining = missing
    completedBytes = 0
    totalBytes = missing.reduce(0) { $0 + $1.expectedSize }
    progressCb = progress
    completionCb = completion
    cancelled = false
    lock.unlock()

    startNext()
  }

  func cancelDownload() {
    lock.lock()
    cancelled = true
    let task = currentTask
    lock.unlock()
    task?.cancel()
  }

  private func startNext() {
    lock.lock()
    guard !cancelled else { lock.unlock(); return }
    guard let next = queueRemaining.first else {
      // All done.
      let cb = completionCb
      let pcb = progressCb
      progressCb = nil
      completionCb = nil
      currentTask = nil
      lock.unlock()
      pcb?(1.0)
      cb?(.success(()))
      return
    }
    let task = session.downloadTask(with: next.downloadURL)
    currentTask = task
    lock.unlock()
    RbLog.diarization.info("downloading \(next.fileName, privacy: .public)")
    task.resume()
  }

  private func fail(_ error: Error) {
    lock.lock()
    let cb = completionCb
    progressCb = nil
    completionCb = nil
    queueRemaining = []
    currentTask = nil
    lock.unlock()
    cb?(.failure(error))
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    lock.lock()
    let completed = completedBytes
    let total = totalBytes
    let cb = progressCb
    lock.unlock()
    guard total > 0, let cb else { return }
    let overall = Double(completed + totalBytesWritten) / Double(total)
    cb(min(0.999, overall))
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    lock.lock()
    guard let file = queueRemaining.first else { lock.unlock(); return }
    lock.unlock()

    let fm = FileManager.default
    let destination = path(for: file)
    let partURL = destination.appendingPathExtension("part")
    do {
      if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
        throw RbNativeError.modelDownloadFailed("HTTP \(http.statusCode) for \(file.fileName)")
      }
      let size = ((try fm.attributesOfItem(atPath: location.path)[.size]) as? NSNumber)?.int64Value ?? 0
      guard size == file.expectedSize else {
        throw RbNativeError.modelDownloadFailed(
          "size mismatch for \(file.fileName) (\(size)/\(file.expectedSize))")
      }
      let digest = try Self.sha256(ofFileAt: location)
      guard digest == file.expectedSHA256 else {
        throw RbNativeError.modelDownloadFailed("checksum mismatch for \(file.fileName)")
      }
      try? fm.removeItem(at: partURL)
      try fm.moveItem(at: location, to: partURL)
      try? fm.removeItem(at: destination)
      try fm.moveItem(at: partURL, to: destination)
    } catch {
      try? fm.removeItem(at: partURL)
      fail(Self.wrap(error))
      return
    }

    lock.lock()
    completedBytes += file.expectedSize
    if !queueRemaining.isEmpty { queueRemaining.removeFirst() }
    lock.unlock()
    startNext()
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error else { return }
    let nsError = error as NSError
    if nsError.code == NSURLErrorCancelled {
      fail(RbNativeError.transcriptionCancelled("diarization download cancelled"))
    } else {
      fail(RbNativeError.modelDownloadFailed(error.localizedDescription))
    }
  }

  // MARK: - Helpers

  private static func wrap(_ error: Error) -> Error {
    error is RbNativeError ? error : RbNativeError.modelDownloadFailed(error.localizedDescription)
  }

  private static func sha256(ofFileAt url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while autoreleasepool(invoking: {
      let chunk = handle.readData(ofLength: 1 << 20)
      guard !chunk.isEmpty else { return false }
      hasher.update(data: chunk)
      return true
    }) {}
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
