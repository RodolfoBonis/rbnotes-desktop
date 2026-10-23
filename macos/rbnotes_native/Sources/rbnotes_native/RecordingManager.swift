import Foundation

/// Owns active [RecordingSession]s keyed by id and implements crash recovery.
final class RecordingManager {
  private var sessions: [String: RecordingSession] = [:]
  private let lock = NSLock()

  func session(for id: String) -> RecordingSession? {
    lock.lock(); defer { lock.unlock() }
    return sessions[id]
  }

  func start(id: String, directory: String, captureSystemAudio: Bool) async throws
    -> [String: Any]
  {
    lock.lock()
    if sessions[id] != nil {
      lock.unlock()
      throw RbNativeError.alreadyRecording("recording already in progress: \(id)")
    }
    lock.unlock()

    let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
    let session = try RecordingSession(
      id: id, directory: dirURL, captureSystemAudio: captureSystemAudio)
    try await session.start()

    lock.lock()
    sessions[id] = session
    lock.unlock()

    return [
      "id": session.id,
      "startedAtMs": Int(session.startedAt.timeIntervalSince1970 * 1000),
    ]
  }

  func stop(id: String) async throws -> [String: Any] {
    lock.lock()
    guard let session = sessions[id] else {
      lock.unlock()
      throw RbNativeError.notRecording("no active recording: \(id)")
    }
    sessions[id] = nil
    lock.unlock()
    return try await session.stop()
  }

  func pause(id: String) throws {
    guard let session = session(for: id) else {
      throw RbNativeError.notRecording("no active recording: \(id)")
    }
    session.pause()
  }

  func resume(id: String) throws {
    guard let session = session(for: id) else {
      throw RbNativeError.notRecording("no active recording: \(id)")
    }
    session.resume()
  }

  /// Scans [directory] for orphaned `<id>.mic.wav` files (no matching `.m4a`,
  /// i.e. the app crashed before `stopRecording`), repairs their headers and
  /// returns recoverable entries.
  func findRecoverable(directory: String) -> [[String: Any]] {
    let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { return [] }

    var results: [[String: Any]] = []
    for name in entries where name.hasSuffix(".mic.wav") {
      let id = String(name.dropLast(".mic.wav".count))
      let micURL = dirURL.appendingPathComponent(name)
      let playbackURL = dirURL.appendingPathComponent("\(id).m4a")
      // A finished recording has a .m4a; skip those.
      if fm.fileExists(atPath: playbackURL.path) { continue }
      // Skip currently active recordings.
      if session(for: id) != nil { continue }

      let micDuration = (try? WavWriter.repairHeader(at: micURL)) ?? 0

      let systemURL = dirURL.appendingPathComponent("\(id).system.wav")
      var systemPath: Any? = nil
      if fm.fileExists(atPath: systemURL.path) {
        _ = try? WavWriter.repairHeader(at: systemURL)
        systemPath = systemURL.path
      }

      results.append([
        "id": id,
        "micWavPath": micURL.path,
        "systemWavPath": systemPath as Any?,
        "durationMs": Int(micDuration * 1000),
      ])
    }
    return results
  }
}
