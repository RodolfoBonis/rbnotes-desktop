import FlutterMacOS
import Foundation

/// Entry point: wires the `rbnotes_native` MethodChannel and the four named
/// EventChannels to the feature managers. Every thrown error is converted to a
/// `FlutterError` carrying a contract error code.
public class RbnotesNativePlugin: NSObject, FlutterPlugin {
  private let recordingManager = RecordingManager()
  private let transcriber = Transcriber()
  private let dictation = DictationManager()

  // Active event sinks.
  private var levelsSink: FlutterEventSink?
  private var levelsId: String?
  private var dictationSink: FlutterEventSink?
  private var progressSinks: [String: FlutterEventSink] = [:]
  private let progressLock = NSLock()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger
    let instance = RbnotesNativePlugin()

    let methodChannel = FlutterMethodChannel(name: "rbnotes_native", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    instance.setupEventChannels(messenger: messenger)
  }

  private func setupEventChannels(messenger: FlutterBinaryMessenger) {
    // Levels.
    FlutterEventChannel(name: "rbnotes_native/levels", binaryMessenger: messenger)
      .setStreamHandler(
        ClosureStreamHandler(
          onListen: { [weak self] args, sink in
            self?.levelsSink = sink
            self?.levelsId = args as? String
            return nil
          },
          onCancel: { [weak self] _ in
            self?.levelsSink = nil
            self?.levelsId = nil
            return nil
          }))

    // Dictation events.
    FlutterEventChannel(name: "rbnotes_native/dictation", binaryMessenger: messenger)
      .setStreamHandler(
        ClosureStreamHandler(
          onListen: { [weak self] _, sink in
            self?.dictationSink = sink
            self?.dictation.onEvent = { [weak self] event in
              self?.emitDictation(event)
            }
            return nil
          },
          onCancel: { [weak self] _ in
            self?.dictationSink = nil
            return nil
          }))

    // Model download (onListen triggers the download).
    FlutterEventChannel(name: "rbnotes_native/model_download", binaryMessenger: messenger)
      .setStreamHandler(
        ClosureStreamHandler(
          onListen: { [weak self] args, sink in
            self?.startDownload(args: args, sink: sink)
            return nil
          },
          onCancel: { _ in nil }))

    // Transcription progress (keyed by wavPath).
    FlutterEventChannel(name: "rbnotes_native/transcription_progress", binaryMessenger: messenger)
      .setStreamHandler(
        ClosureStreamHandler(
          onListen: { [weak self] args, sink in
            guard let wavPath = args as? String else { return nil }
            self?.progressLock.lock()
            self?.progressSinks[wavPath] = sink
            self?.progressLock.unlock()
            return nil
          },
          onCancel: { [weak self] args in
            if let wavPath = args as? String {
              self?.progressLock.lock()
              self?.progressSinks[wavPath] = nil
              self?.progressLock.unlock()
            }
            return nil
          }))
  }

  // MARK: - Method dispatch

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "permissionStatus":
      handlePermissionStatus(args, result)
    case "requestPermission":
      handleRequestPermission(args, result)
    case "startRecording":
      handleStartRecording(args, result)
    case "stopRecording":
      handleStopRecording(args, result)
    case "pauseRecording":
      runSync(result) { try self.recordingManager.pause(id: self.requireString(args, "id")) }
    case "resumeRecording":
      runSync(result) { try self.recordingManager.resume(id: self.requireString(args, "id")) }
    case "findRecoverableRecordings":
      let directory = (args["directory"] as? String) ?? ""
      reply(result, recordingManager.findRecoverable(directory: directory))
    case "modelState":
      handleModelState(args, result)
    case "transcribe":
      handleTranscribe(args, result)
    case "cancelTranscription":
      if let wavPath = args["wavPath"] as? String { transcriber.cancel(wavPath: wavPath) }
      reply(result, nil)
    case "registerDictationHotkey":
      handleRegisterHotkey(args, result)
    case "unregisterDictationHotkey":
      dictation.unregister()
      reply(result, nil)
    case "pasteText":
      runSync(result) { try self.dictation.pasteText(self.requireString(args, "text")) }
    case "playDictationSound":
      let sound = DictationSoundKind(rawValue: (args["sound"] as? String) ?? "start") ?? .start
      dictation.playSound(sound)
      reply(result, nil)
    default:
      reply(result, FlutterMethodNotImplemented)
    }
  }

  // MARK: - Handlers

  private func handlePermissionStatus(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let raw = args["permission"] as? String, let permission = Permission(rawValue: raw) else {
      return reply(result, FlutterError(code: "unknown", message: "bad permission", details: nil))
    }
    reply(result, Permissions.status(permission).rawValue)
  }

  private func handleRequestPermission(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let raw = args["permission"] as? String, let permission = Permission(rawValue: raw) else {
      return reply(result, FlutterError(code: "unknown", message: "bad permission", details: nil))
    }
    Permissions.request(permission) { [weak self] status in
      self?.reply(result, status.rawValue)
    }
  }

  private func handleStartRecording(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["id"] as? String, let directory = args["directory"] as? String else {
      return reply(result, FlutterError(code: "unknown", message: "missing args", details: nil))
    }
    let captureSystemAudio = (args["captureSystemAudio"] as? Bool) ?? false
    Task {
      do {
        let map = try await recordingManager.start(
          id: id, directory: directory, captureSystemAudio: captureSystemAudio)
        // Wire levels forwarding for this session.
        recordingManager.session(for: id)?.onLevels = { [weak self] payload in
          guard let self, self.levelsId == id, let sink = self.levelsSink else { return }
          emit(sink, payload)
        }
        reply(result, map)
      } catch {
        reply(result, FlutterError.from(error))
      }
    }
  }

  private func handleStopRecording(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["id"] as? String else {
      return reply(result, FlutterError(code: "unknown", message: "missing id", details: nil))
    }
    Task {
      do {
        let map = try await recordingManager.stop(id: id)
        reply(result, map)
      } catch {
        reply(result, FlutterError.from(error))
      }
    }
  }

  private func handleModelState(_ args: [String: Any], _ result: @escaping FlutterResult) {
    do {
      let model = try WhisperModelKind(wire: requireString(args, "model"))
      reply(result, ModelManager.shared.state(model))
    } catch {
      reply(result, FlutterError.from(error))
    }
  }

  private func handleTranscribe(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let wavPath = args["wavPath"] as? String, let modelRaw = args["model"] as? String else {
      return reply(result, FlutterError(code: "unknown", message: "missing args", details: nil))
    }
    let language = (args["language"] as? String) ?? "pt"
    Task {
      do {
        let model = try WhisperModelKind(wire: modelRaw)
        let segments = try await transcriber.transcribe(
          wavPath: wavPath, model: model, language: language,
          onProgress: { [weak self] progress in
            self?.emitProgress(wavPath: wavPath, progress: progress)
          })
        reply(result, segments)
      } catch {
        reply(result, FlutterError.from(error))
      }
    }
  }

  private func handleRegisterHotkey(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let hotkey = args["hotkey"] as? [String: Any],
      let keyCode = hotkey["keyCode"] as? Int,
      let modeRaw = args["mode"] as? String,
      let mode = DictationModeKind(rawValue: modeRaw)
    else {
      return reply(result, FlutterError(code: "unknown", message: "bad hotkey args", details: nil))
    }
    let modifiers = (hotkey["modifiers"] as? [String]) ?? []
    // Carbon/event-tap APIs must be touched on the main thread.
    DispatchQueue.main.async { [weak self] in
      do {
        try self?.dictation.register(keyCode: keyCode, modifiers: modifiers, mode: mode)
        self?.reply(result, nil)
      } catch {
        self?.reply(result, FlutterError.from(error))
      }
    }
  }

  // MARK: - Emit helpers

  private func emitDictation(_ event: DictationEventKind) {
    guard let sink = dictationSink else { return }
    switch event {
    case .started:
      emit(sink, ["type": "started"])
    case .stopped(let path):
      emit(sink, ["type": "stopped", "wavPath": path])
    case .cancelled:
      emit(sink, ["type": "cancelled"])
    }
  }

  private func emitProgress(wavPath: String, progress: Double) {
    progressLock.lock()
    let sink = progressSinks[wavPath]
    progressLock.unlock()
    if let sink { emit(sink, progress) }
  }

  private func startDownload(args: Any?, sink: @escaping FlutterEventSink) {
    guard let raw = args as? String, let model = try? WhisperModelKind(wire: raw) else {
      emit(sink, FlutterError(code: "model_download_failed", message: "bad model", details: nil))
      emit(sink, FlutterEndOfEventStream)
      return
    }
    ModelManager.shared.download(
      model,
      progress: { progress in emit(sink, progress) },
      completion: { completionResult in
        switch completionResult {
        case .success:
          emit(sink, 1.0)
          emit(sink, FlutterEndOfEventStream)
        case .failure(let error):
          emit(sink, FlutterError.from(error))
          emit(sink, FlutterEndOfEventStream)
        }
      })
  }

  // MARK: - Reply plumbing

  private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    if Thread.isMainThread {
      result(value)
    } else {
      DispatchQueue.main.async { result(value) }
    }
  }

  private func runSync(_ result: @escaping FlutterResult, _ work: () throws -> Void) {
    do {
      try work()
      reply(result, nil)
    } catch {
      reply(result, FlutterError.from(error))
    }
  }

  private func requireString(_ args: [String: Any], _ key: String) -> String {
    (args[key] as? String) ?? ""
  }
}
