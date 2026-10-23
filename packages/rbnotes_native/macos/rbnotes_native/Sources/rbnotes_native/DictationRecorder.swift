import Foundation

/// Mic-only recorder used by global dictation: writes a temporary 16 kHz mono
/// wav that the app transcribes.
final class DictationRecorder {
  private let capture = AudioCapture()
  private var writer: WavWriter?
  private let writeQueue = DispatchQueue(label: "br.com.rodolfodebonis.rbnotes.dictation.wav")
  private(set) var wavURL: URL?

  func start() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("rbnotes-dictation-\(UUID().uuidString).wav")
    let writer = try WavWriter(url: url)
    self.writer = writer
    self.wavURL = url
    capture.onData = { [weak self, weak writer] data in
      self?.writeQueue.async { try? writer?.append(data) }
    }
    try capture.start()
    return url
  }

  /// Stops and finalizes the wav, returning its path.
  func stop() -> URL? {
    capture.stop()
    writeQueue.sync {}
    try? writer?.finalize()
    let url = wavURL
    writer = nil
    wavURL = nil
    return url
  }

  /// Stops and discards the temporary wav.
  func cancel() {
    capture.stop()
    writeQueue.sync {}
    try? writer?.finalize()
    if let url = wavURL { try? FileManager.default.removeItem(at: url) }
    writer = nil
    wavURL = nil
  }
}
