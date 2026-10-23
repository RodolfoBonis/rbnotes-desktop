import FlutterMacOS
import Foundation

/// Entry point: wires the `rbnotes_native` MethodChannel and the named
/// EventChannels to the feature managers. Every thrown error is converted to a
/// `FlutterError` carrying a contract error code.
///
/// All `FlutterEventSink`s are confined to the main (platform) thread: they are
/// only ever read/written inside `onMain`, and Flutter's `onListen`/`onCancel`
/// already run there.
public class RbnotesNativePlugin: NSObject, FlutterPlugin {
  private let recordingManager = RecordingManager()
  private let transcriber = Transcriber()
  private let dictation = DictationManager()

  // Active event sinks — MAIN-THREAD ONLY.
  private var levelsSink: FlutterEventSink?
  private var levelsId: String?
  private var dictationSink: FlutterEventSink?
  private var diagnosticsSink: FlutterEventSink?
  // Single, permanent transcription-progress stream: emits {wavPath, progress}.
  private var progressSink: FlutterEventSink?
  // Single, permanent live-transcript stream: emits {recordingId, text, isFinal}.
  private var liveTranscriptSink: FlutterEventSink?
  // Single, permanent overlay-actions stream: emits a wire action name string.
  private var overlayActionsSink: FlutterEventSink?
  // Notch activity overlay controller (macOS 13+); created lazily on first use.
  private var _overlay: AnyObject?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger
    let instance = RbnotesNativePlugin()

    let methodChannel = FlutterMethodChannel(name: "rbnotes_native", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    instance.wireDiagnostics()
    instance.setupEventChannels(messenger: messenger)
  }

  private func wireDiagnostics() {
    recordingManager.onDiagnostic = { [weak self] diag in self?.emitDiagnostic(diag) }
    dictation.onDiagnostic = { [weak self] diag in self?.emitDiagnostic(diag) }
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

    // Diagnostics: a single permanent stream of async native failures.
    FlutterEventChannel(name: "rbnotes_native/diagnostics", binaryMessenger: messenger)
      .setStreamHandler(
        ClosureStreamHandler(
          onListen: { [weak self] _, sink in
            self?.diagnosticsSink = sink
            return nil
          },
          onCancel: { [weak self] _ in
            self?.diagnosticsSink = nil
            return nil
          }))

    // Model download (onListen triggers the download; onCancel cancels it).
    FlutterEventChannel(name: "rbnotes_native/model_download", binaryMessenger: messenger)
      .setStreamHandler(
        ClosureStreamHandler(
          onListen: { [weak self] args, sink in
            self?.startDownload(args: args, sink: sink)
            return nil
          },
          onCancel: { args in
            if let raw = args as? String, let model = try? WhisperModelKind(wire: raw) {
              ModelManager.shared.cancelDownload(model)
            }
            return nil
          }))

    // Transcription progress: single permanent stream, emits {wavPath, progress}.
    FlutterEventChannel(name: "rbnotes_native/transcription_progress", binaryMessenger: messenger)
      .setStreamHandler(
        ClosureStreamHandler(
          onListen: { [weak self] _, sink in
            self?.progressSink = sink
            return nil
          },
          onCancel: { [weak self] _ in
            self?.progressSink = nil
            return nil
          }))

    // Live transcript: single permanent stream, emits {recordingId, text, isFinal}.
    FlutterEventChannel(name: "rbnotes_native/live_transcript", binaryMessenger: messenger)
      .setStreamHandler(
        ClosureStreamHandler(
          onListen: { [weak self] _, sink in
            self?.liveTranscriptSink = sink
            return nil
          },
          onCancel: { [weak self] _ in
            self?.liveTranscriptSink = nil
            return nil
          }))

    // Overlay actions: single permanent stream, emits a wire action name string.
    FlutterEventChannel(name: "rbnotes_native/overlay_actions", binaryMessenger: messenger)
      .setStreamHandler(
        ClosureStreamHandler(
          onListen: { [weak self] _, sink in
            self?.overlayActionsSink = sink
            return nil
          },
          onCancel: { [weak self] _ in
            self?.overlayActionsSink = nil
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
      do {
        let directory = try requireString(args, "directory")
        reply(result, recordingManager.findRecoverable(directory: directory))
      } catch {
        reply(result, FlutterError.from(error))
      }
    case "inputDevices":
      reply(result, AudioDevices.inputDevices())
    case "waveformPeaks":
      handleWaveformPeaks(args, result)
    case "modelState":
      handleModelState(args, result)
    case "deleteModel":
      handleDeleteModel(args, result)
    case "transcribe":
      handleTranscribe(args, result)
    case "cancelTranscription":
      runSync(result) { self.transcriber.cancel(wavPath: try self.requireString(args, "wavPath")) }
    case "registerDictationHotkey":
      handleRegisterHotkey(args, result)
    case "unregisterDictationHotkey":
      dictation.unregister()
      reply(result, nil)
    case "pasteText":
      runSync(result) { try self.dictation.pasteText(self.requireString(args, "text")) }
    case "playDictationSound":
      handlePlayDictationSound(args, result)
    case "showActivityOverlay":
      handleShowOverlay(args, result)
    case "updateActivityOverlay":
      handleUpdateOverlay(args, result)
    case "hideActivityOverlay":
      handleHideOverlay(args, result)
    default:
      reply(result, FlutterMethodNotImplemented)
    }
  }

  // MARK: - Handlers

  private func handlePermissionStatus(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let raw = args["permission"] as? String, let permission = Permission(rawValue: raw) else {
      return reply(result, RbNativeError.invalidArgument("unknown permission").flutterError)
    }
    reply(result, Permissions.status(permission).rawValue)
  }

  private func handleRequestPermission(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let raw = args["permission"] as? String, let permission = Permission(rawValue: raw) else {
      return reply(result, RbNativeError.invalidArgument("unknown permission").flutterError)
    }
    Permissions.request(permission) { [weak self] status in
      self?.reply(result, status.rawValue)
    }
  }

  private func handleStartRecording(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["id"] as? String, let directory = args["directory"] as? String else {
      return reply(result, RbNativeError.invalidArgument("startRecording requires id, directory").flutterError)
    }
    guard let captureSystemAudio = args["captureSystemAudio"] as? Bool else {
      return reply(result, RbNativeError.invalidArgument("captureSystemAudio must be a bool").flutterError)
    }
    let liveTranscription = (args["liveTranscription"] as? Bool) ?? false
    let inputDeviceId = args["inputDeviceId"] as? String
    Task {
      do {
        let map = try await recordingManager.start(
          id: id, directory: directory, captureSystemAudio: captureSystemAudio,
          liveTranscription: liveTranscription, inputDeviceId: inputDeviceId)
        // Wire levels + live-transcript forwarding for this session (sinks read
        // on main only).
        recordingManager.session(for: id)?.onLevels = { [weak self] payload in
          self?.forwardLevels(id: id, payload: payload)
        }
        recordingManager.session(for: id)?.onLiveTranscript = { [weak self] text, isFinal in
          self?.emitLiveTranscript(id: id, text: text, isFinal: isFinal)
        }
        reply(result, map)
      } catch {
        reply(result, FlutterError.from(error))
      }
    }
  }

  private func handleStopRecording(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["id"] as? String else {
      return reply(result, RbNativeError.invalidArgument("stopRecording requires id").flutterError)
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

  private func handleWaveformPeaks(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let path = args["path"] as? String, let buckets = args["buckets"] as? Int else {
      return reply(result, RbNativeError.invalidArgument("waveformPeaks requires path, buckets").flutterError)
    }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let peaks = try Waveform.peaks(path: path, buckets: buckets)
        self?.reply(result, peaks)
      } catch {
        self?.reply(result, FlutterError.from(error))
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

  private func handleDeleteModel(_ args: [String: Any], _ result: @escaping FlutterResult) {
    runSync(result) {
      let model = try WhisperModelKind(wire: self.requireString(args, "model"))
      try ModelManager.shared.delete(model)
    }
  }

  private func handleTranscribe(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let wavPath = args["wavPath"] as? String, let modelRaw = args["model"] as? String else {
      return reply(result, RbNativeError.invalidArgument("transcribe requires wavPath, model").flutterError)
    }
    let language = (args["language"] as? String) ?? "pt"
    let initialPrompt = args["initialPrompt"] as? String
    Task {
      do {
        let model = try WhisperModelKind(wire: modelRaw)
        let priority = try TranscriptionPriority(wire: args["priority"] as? String)
        let segments = try await transcriber.transcribe(
          wavPath: wavPath, model: model, language: language, initialPrompt: initialPrompt,
          priority: priority,
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
      return reply(result, RbNativeError.invalidArgument("bad hotkey args").flutterError)
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

  private func handlePlayDictationSound(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let raw = args["sound"] as? String, let sound = DictationSoundKind(rawValue: raw) else {
      return reply(result, RbNativeError.invalidArgument("unknown dictation sound").flutterError)
    }
    dictation.playSound(sound)
    reply(result, nil)
  }

  // MARK: - Activity overlay

  /// Lazily-created overlay controller (macOS 13+). Returns nil on older
  /// systems, where the overlay methods become no-ops.
  @available(macOS 13.0, *)
  private var overlay: ActivityOverlayController {
    if let existing = _overlay as? ActivityOverlayController { return existing }
    let controller = ActivityOverlayController()
    controller.onAction = { [weak self] name in self?.emitOverlayAction(name) }
    _overlay = controller
    return controller
  }

  private func handleShowOverlay(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let modeRaw = args["mode"] as? String, let mode = OverlayMode(rawValue: modeRaw),
      let startedMs = args["startedAtMs"] as? Int
    else {
      return reply(result, RbNativeError.invalidArgument("showActivityOverlay requires mode, startedAtMs").flutterError)
    }
    let startedAt = Date(timeIntervalSince1970: Double(startedMs) / 1000)
    onMain { [weak self] in
      if #available(macOS 13.0, *) {
        self?.overlay.show(mode: mode, startedAt: startedAt)
      }
      self?.reply(result, nil)
    }
  }

  private func handleUpdateOverlay(_ args: [String: Any], _ result: @escaping FlutterResult) {
    // All fields optional; an unknown phase string is an invalid argument.
    var phase: OverlayPhase?
    if let raw = args["phase"] as? String {
      guard let p = OverlayPhase(rawValue: raw) else {
        return reply(result, RbNativeError.invalidArgument("unknown overlay phase '\(raw)'").flutterError)
      }
      phase = p
    }
    let mic = (args["micLevel"] as? NSNumber)?.doubleValue
    let sys = (args["systemLevel"] as? NSNumber)?.doubleValue
    let liveText = args["liveText"] as? String
    let progress = (args["progress"] as? NSNumber)?.doubleValue
    let message = args["message"] as? String
    let paused = args["paused"] as? Bool
    onMain { [weak self] in
      if #available(macOS 13.0, *) {
        self?.overlay.update(
          micLevel: mic, systemLevel: sys, liveText: liveText, phase: phase,
          progress: progress, message: message, paused: paused)
      }
      self?.reply(result, nil)
    }
  }

  private func handleHideOverlay(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let delayMs = (args["delayMs"] as? Int) ?? 0
    onMain { [weak self] in
      if #available(macOS 13.0, *) {
        self?.overlay.hide(delayMs: delayMs)
      }
      self?.reply(result, nil)
    }
  }

  private func emitOverlayAction(_ name: String) {
    onMain { [weak self] in
      guard let self, let sink = self.overlayActionsSink else { return }
      sink(name)
    }
  }

  // MARK: - Emit helpers (main-thread confined)

  private func onMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
  }

  private func forwardLevels(id: String, payload: [String: Any]) {
    onMain { [weak self] in
      guard let self, self.levelsId == id, let sink = self.levelsSink else { return }
      sink(payload)
    }
  }

  private func emitLiveTranscript(id: String, text: String, isFinal: Bool) {
    onMain { [weak self] in
      guard let self, let sink = self.liveTranscriptSink else { return }
      sink(["recordingId": id, "text": text, "isFinal": isFinal])
    }
  }

  private func emitDictation(_ event: DictationEventKind) {
    onMain { [weak self] in
      guard let self, let sink = self.dictationSink else { return }
      switch event {
      case .started: sink(["type": "started"])
      case .stopped(let path): sink(["type": "stopped", "wavPath": path])
      case .cancelled: sink(["type": "cancelled"])
      }
    }
  }

  private func emitProgress(wavPath: String, progress: Double) {
    onMain { [weak self] in
      guard let self, let sink = self.progressSink else { return }
      sink(["wavPath": wavPath, "progress": progress])
    }
  }

  private func emitDiagnostic(_ diagnostic: NativeDiagnostic) {
    onMain { [weak self] in
      guard let self, let sink = self.diagnosticsSink else { return }
      sink(diagnostic.map)
    }
  }

  private func startDownload(args: Any?, sink: @escaping FlutterEventSink) {
    guard let raw = args as? String, let model = try? WhisperModelKind(wire: raw) else {
      emit(sink, RbNativeError.invalidArgument("bad model").flutterError)
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

  /// Runs [work]; on throw, replies a mapped `FlutterError`. [work] either
  /// replies itself or leaves the default `nil` reply to this method.
  private func runSync(_ result: @escaping FlutterResult, _ work: () throws -> Void) {
    do {
      try work()
      reply(result, nil)
    } catch {
      reply(result, FlutterError.from(error))
    }
  }

  /// Returns the string at [key] or throws `invalid_argument`.
  private func requireString(_ args: [String: Any], _ key: String) throws -> String {
    guard let value = args[key] as? String else {
      throw RbNativeError.invalidArgument("missing or invalid '\(key)'")
    }
    return value
  }
}
