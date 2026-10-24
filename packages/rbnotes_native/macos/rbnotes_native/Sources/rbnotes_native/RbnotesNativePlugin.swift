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
  private let globalHotkeys = GlobalHotkeyManager()
  private let lockTriggers = LockTriggerManager()
  private let meetingDetector = MeetingDetector()

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
  // Single, permanent global-hotkey stream: emits the pressed hotkey's id.
  private var globalHotkeysSink: FlutterEventSink?
  // Single, permanent app-lock-trigger stream: emits a wire trigger name.
  private var lockTriggersSink: FlutterEventSink?
  // Single, permanent meeting-signal stream: emits {app, micInUse, startedAtMs}.
  private var meetingSignalsSink: FlutterEventSink?
  // Single, permanent diarization-download progress stream (onListen triggers it).
  private var diarizationDownloadSink: FlutterEventSink?
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

  /// Tears down global hotkeys and the dictation hotkey. The plugin normally
  /// lives for the whole app lifetime, but we unregister on dealloc so a hot
  /// reload / re-registration never leaks Carbon hot keys or event handlers.
  deinit {
    let hotkeys = globalHotkeys
    let dictationManager = dictation
    let lock = lockTriggers
    let meeting = meetingDetector
    let cleanup = {
      hotkeys.unregisterAll()
      dictationManager.unregister()
      lock.stop()
      meeting.setEnabled(false)
    }
    if Thread.isMainThread { cleanup() } else { DispatchQueue.main.async(execute: cleanup) }
  }

  private func wireDiagnostics() {
    recordingManager.onDiagnostic = { [weak self] diag in self?.emitDiagnostic(diag) }
    dictation.onDiagnostic = { [weak self] diag in self?.emitDiagnostic(diag) }
    globalHotkeys.onPressed = { [weak self] id in self?.emitGlobalHotkey(id) }
    // Reject a global hotkey that would collide with the dictation shortcut.
    globalHotkeys.dictationCombo = { [weak self] in self?.dictation.activeHotkey }
    lockTriggers.onTrigger = { [weak self] name in self?.emitLockTrigger(name) }
    lockTriggers.start()
    meetingDetector.onSignal = { [weak self] app, inUse, startedAt in
      self?.emitMeetingSignal(app: app, micInUse: inUse, startedAt: startedAt)
    }
    meetingDetector.isSelfUsingMic = { [weak self] in
      self?.recordingManager.hasActiveRecording ?? false
    }
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

    // Global hotkeys: single permanent stream, emits the pressed hotkey's id.
    FlutterEventChannel(name: "rbnotes_native/global_hotkeys", binaryMessenger: messenger)
      .setStreamHandler(
        ClosureStreamHandler(
          onListen: { [weak self] _, sink in
            self?.globalHotkeysSink = sink
            return nil
          },
          onCancel: { [weak self] _ in
            self?.globalHotkeysSink = nil
            return nil
          }))

    // App lock triggers: single permanent stream, emits a wire trigger name.
    FlutterEventChannel(name: "rbnotes_native/lock_triggers", binaryMessenger: messenger)
      .setStreamHandler(
        ClosureStreamHandler(
          onListen: { [weak self] _, sink in
            self?.lockTriggersSink = sink
            return nil
          },
          onCancel: { [weak self] _ in
            self?.lockTriggersSink = nil
            return nil
          }))

    // Meeting signals: single permanent stream, emits {app, micInUse, startedAtMs}.
    FlutterEventChannel(name: "rbnotes_native/meeting_signals", binaryMessenger: messenger)
      .setStreamHandler(
        ClosureStreamHandler(
          onListen: { [weak self] _, sink in
            self?.meetingSignalsSink = sink
            return nil
          },
          onCancel: { [weak self] _ in
            self?.meetingSignalsSink = nil
            return nil
          }))

    // Diarization model download (onListen triggers it; onCancel cancels it).
    FlutterEventChannel(name: "rbnotes_native/diarization_download", binaryMessenger: messenger)
      .setStreamHandler(
        ClosureStreamHandler(
          onListen: { [weak self] _, sink in
            self?.startDiarizationDownload(sink: sink)
            return nil
          },
          onCancel: { _ in
            DiarizationModelManager.shared.cancelDownload()
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
    case "registerGlobalHotkey":
      handleRegisterGlobalHotkey(args, result)
    case "unregisterGlobalHotkey":
      handleUnregisterGlobalHotkey(args, result)
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
    case "launchAtLogin":
      reply(result, LoginItem.isEnabled())
    case "setLaunchAtLogin":
      handleSetLaunchAtLogin(args, result)
    case "detectSilences":
      handleDetectSilences(args, result)
    case "setMeetingDetection":
      handleSetMeetingDetection(args, result)
    case "diarizationModelState":
      reply(result, DiarizationModelManager.shared.state())
    case "diarize":
      handleDiarize(args, result)
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
    let noiseReduction = (args["noiseReduction"] as? Bool) ?? false
    let language = args["language"] as? String
    Task {
      do {
        let map = try await recordingManager.start(
          id: id, directory: directory, captureSystemAudio: captureSystemAudio,
          liveTranscription: liveTranscription, inputDeviceId: inputDeviceId,
          noiseReduction: noiseReduction, language: language)
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

  private func handleRegisterGlobalHotkey(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["id"] as? String, let hotkey = args["hotkey"] as? [String: Any],
      let keyCode = hotkey["keyCode"] as? Int
    else {
      return reply(result, RbNativeError.invalidArgument("registerGlobalHotkey requires id, hotkey.keyCode").flutterError)
    }
    let modifiers = (hotkey["modifiers"] as? [String]) ?? []
    // Carbon APIs must be touched on the main thread.
    DispatchQueue.main.async { [weak self] in
      do {
        try self?.globalHotkeys.register(id: id, keyCode: keyCode, modifiers: modifiers)
        self?.reply(result, nil)
      } catch {
        self?.reply(result, FlutterError.from(error))
      }
    }
  }

  private func handleUnregisterGlobalHotkey(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["id"] as? String else {
      return reply(result, RbNativeError.invalidArgument("unregisterGlobalHotkey requires id").flutterError)
    }
    DispatchQueue.main.async { [weak self] in
      self?.globalHotkeys.unregister(id)
      self?.reply(result, nil)
    }
  }

  private func handlePlayDictationSound(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let raw = args["sound"] as? String, let sound = DictationSoundKind(rawValue: raw) else {
      return reply(result, RbNativeError.invalidArgument("unknown dictation sound").flutterError)
    }
    dictation.playSound(sound)
    reply(result, nil)
  }

  // MARK: - Phase 3 handlers

  private func handleSetLaunchAtLogin(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let enabled = args["enabled"] as? Bool else {
      return reply(result, RbNativeError.invalidArgument("setLaunchAtLogin requires enabled").flutterError)
    }
    // SMAppService must be touched on the main thread.
    onMain { [weak self] in
      do {
        try LoginItem.setEnabled(enabled)
        self?.reply(result, nil)
      } catch {
        self?.reply(result, FlutterError.from(error))
      }
    }
  }

  private func handleDetectSilences(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let wavPath = args["wavPath"] as? String else {
      return reply(result, RbNativeError.invalidArgument("detectSilences requires wavPath").flutterError)
    }
    let minSilenceMs = (args["minSilenceMs"] as? Int) ?? 2000
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let ranges = try SilenceAnalyzer.detect(wavPath: wavPath, minSilenceMs: minSilenceMs)
        self?.reply(result, ranges)
      } catch {
        self?.reply(result, FlutterError.from(error))
      }
    }
  }

  private func handleSetMeetingDetection(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let enabled = args["enabled"] as? Bool else {
      return reply(result, RbNativeError.invalidArgument("setMeetingDetection requires enabled").flutterError)
    }
    meetingDetector.setEnabled(enabled)
    reply(result, nil)
  }

  private func handleDiarize(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let wavPath = args["wavPath"] as? String else {
      return reply(result, RbNativeError.invalidArgument("diarize requires wavPath").flutterError)
    }
    let numSpeakers = args["numSpeakers"] as? Int
    // Diarization is CPU-heavy — keep it off the main thread.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let turns = try Diarization.run(wavPath: wavPath, numSpeakers: numSpeakers)
        self?.reply(result, turns)
      } catch {
        self?.reply(result, FlutterError.from(error))
      }
    }
  }

  private func startDiarizationDownload(sink: @escaping FlutterEventSink) {
    DiarizationModelManager.shared.download(
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
    let accentArgb = (args["accentArgb"] as? NSNumber)?.intValue
    onMain { [weak self] in
      if #available(macOS 13.0, *) {
        self?.overlay.show(mode: mode, startedAt: startedAt, accentArgb: accentArgb)
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

  private func emitGlobalHotkey(_ id: String) {
    onMain { [weak self] in
      guard let self, let sink = self.globalHotkeysSink else { return }
      sink(id)
    }
  }

  private func emitLockTrigger(_ name: String) {
    onMain { [weak self] in
      guard let self, let sink = self.lockTriggersSink else { return }
      sink(name)
    }
  }

  private func emitMeetingSignal(app: String, micInUse: Bool, startedAt: Date) {
    onMain { [weak self] in
      guard let self, let sink = self.meetingSignalsSink else { return }
      sink([
        "app": app,
        "micInUse": micInUse,
        "startedAtMs": Int(startedAt.timeIntervalSince1970 * 1000),
      ])
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
