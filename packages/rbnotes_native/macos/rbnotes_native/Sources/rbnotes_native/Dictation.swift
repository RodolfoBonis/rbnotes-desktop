import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Dictation hotkey behaviour, matching the Dart `DictationMode`.
enum DictationModeKind: String {
  case toggle
  case holdToTalk
}

/// Events pushed to the Dart dictation EventChannel.
enum DictationEventKind {
  case started
  case stopped(String)
  case cancelled
}

private let kEscKeyCode: Int64 = 53
private let kFallbackVKeyCode: UInt16 = 9

/// Max dictation duration before the watchdog force-stops it (safety against a
/// stuck key / missed keyUp).
private let kMaxDictationSeconds: TimeInterval = 300

/// `NSPasteboard` adapter for the pure `PasteboardManager` logic.
private final class SystemPasteboard: PasteboardLike {
  private let pb = NSPasteboard.general
  var changeCount: Int { pb.changeCount }

  func readItems() -> [[String: Data]] {
    guard let items = pb.pasteboardItems else { return [] }
    return items.map { item in
      var dict: [String: Data] = [:]
      for type in item.types {
        if let data = item.data(forType: type) { dict[type.rawValue] = data }
      }
      return dict
    }
  }

  @discardableResult func clear() -> Int { pb.clearContents() }

  func writeTemporaryString(_ text: String, transientTypes: [String]) {
    let item = NSPasteboardItem()
    item.setString(text, forType: .string)
    for type in transientTypes {
      item.setData(Data(), forType: NSPasteboard.PasteboardType(type))
    }
    pb.writeObjects([item])
  }

  func writeItems(_ items: [[String: Data]]) {
    let objects = items.map { dict -> NSPasteboardItem in
      let item = NSPasteboardItem()
      for (type, data) in dict { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
      return item
    }
    pb.writeObjects(objects)
  }
}

/// Global dictation: a Carbon hotkey (toggle) or a CGEventTap (hold-to-talk),
/// an Esc-to-cancel tap, temporary mic recording, text pasting and sounds.
///
/// Requires Accessibility permission (event tap + synthetic ⌘V).
final class DictationManager {
  private var mode: DictationModeKind = .toggle
  private var targetKeyCode: UInt16 = 0
  private var requiredFlags: CGEventFlags = []
  /// Original modifier wire-names of the registered hotkey, kept so other
  /// subsystems (global hotkeys) can detect a conflict with the dictation combo.
  private var modifierNames: [String] = []

  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  private let recorder = DictationRecorder()
  private var isRecording = false
  private let stateLock = NSLock()
  private var watchdog: DispatchSourceTimer?

  /// Set by the plugin to forward events to the EventChannel.
  var onEvent: ((DictationEventKind) -> Void)?
  /// Set by the plugin to forward diagnostics (tap disabled, watchdog, …).
  var onDiagnostic: ((NativeDiagnostic) -> Void)?

  /// The currently registered dictation combo, or nil when not registered.
  /// Used by `GlobalHotkeyManager` to reject a conflicting global hotkey.
  var activeHotkey: HotkeyCombo? {
    guard hotKeyRef != nil || eventTap != nil else { return nil }
    return HotkeyCombo(keyCode: Int(targetKeyCode), modifiers: Set(modifierNames))
  }

  // MARK: - Registration

  func register(keyCode: Int, modifiers: [String], mode: DictationModeKind) throws {
    unregister()
    self.mode = mode
    self.targetKeyCode = UInt16(keyCode)
    self.requiredFlags = Self.cgFlags(modifiers)
    self.modifierNames = modifiers

    switch mode {
    case .toggle:
      // Carbon owns the shortcut; the tap is optional (Esc-to-cancel only).
      try registerCarbonHotKey(keyCode: keyCode, modifiers: modifiers)
      do {
        try installEventTap(consumesShortcut: false)
      } catch {
        RbLog.dictation.error(
          "Esc-cancel tap unavailable (toggle mode continues): \(error.localizedDescription)")
      }
    case .holdToTalk:
      // The tap is mandatory: it both detects the key and consumes it so the
      // shortcut does not type into the focused app.
      do {
        try installEventTap(consumesShortcut: true)
      } catch {
        // Nothing to undo (no Carbon hotkey in hold-to-talk); surface as a
        // permission problem, not a hotkey conflict.
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        throw RbNativeError.permissionDenied(
          "Accessibility permission required for hold-to-talk dictation")
      }
    }
    RbLog.dictation.info("dictation registered (mode=\(mode.rawValue, privacy: .public))")
  }

  func unregister() {
    if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
    if let eventHandlerRef { RemoveEventHandler(eventHandlerRef); self.eventHandlerRef = nil }
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      if let runLoopSource {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      }
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
      self.runLoopSource = nil
    }
    if recordingState { cancelRecording() }
  }

  // MARK: - Carbon hotkey (toggle)

  private func registerCarbonHotKey(keyCode: Int, modifiers: [String]) throws {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData -> OSStatus in
        // Only react to *our* hotkey: other installed handlers (e.g. the
        // global-hotkey manager) register on the same target, so route by id
        // and let anyone else's press fall through (eventNotHandledErr).
        guard let userData, let event else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
          event, EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        guard status == noErr, hotKeyID.signature == OSType(0x5242_4E54),
          hotKeyID.id == 1
        else { return OSStatus(eventNotHandledErr) }
        let manager = Unmanaged<DictationManager>.fromOpaque(userData).takeUnretainedValue()
        manager.handleToggle()
        return noErr
      },
      1, &eventType, selfPtr, &eventHandlerRef)
    guard handlerStatus == noErr else {
      throw RbNativeError.hotkeyConflict("InstallEventHandler failed (\(handlerStatus))")
    }

    let hotKeyID = EventHotKeyID(signature: OSType(0x5242_4E54), id: 1)  // 'RBNT'
    let status = RegisterEventHotKey(
      UInt32(keyCode), Self.carbonModifiers(modifiers), hotKeyID,
      GetApplicationEventTarget(), 0, &hotKeyRef)
    guard status == noErr else {
      if let eventHandlerRef { RemoveEventHandler(eventHandlerRef); self.eventHandlerRef = nil }
      throw RbNativeError.hotkeyConflict("RegisterEventHotKey failed (\(status))")
    }
  }

  private func handleToggle() {
    if recordingState { stopRecording() } else { startRecording() }
  }

  // MARK: - Event tap

  private func installEventTap(consumesShortcut: Bool) throws {
    let mask =
      (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    // `.defaultTap` so we can consume the shortcut's key events in
    // hold-to-talk (and Esc while recording); listen-only cannot drop events.
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: CGEventMask(mask),
        callback: { _, type, event, userData -> Unmanaged<CGEvent>? in
          guard let userData else { return Unmanaged.passUnretained(event) }
          let manager = Unmanaged<DictationManager>.fromOpaque(userData).takeUnretainedValue()
          return manager.handleTap(type: type, event: event)
        },
        userInfo: selfPtr)
    else {
      throw RbNativeError.permissionDenied(
        "CGEventTapCreate failed — Accessibility permission required")
    }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    self.eventTap = tap
    self.runLoopSource = source
  }

  /// Returns the event to pass through, or nil to consume it.
  private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    // Re-enable the tap if the system disabled it (timeout / user input).
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      RbLog.dictation.notice("event tap disabled (\(type.rawValue)); re-enabling")
      if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
      // If a hold-to-talk dictation was in flight we may have missed the keyUp;
      // stop it safely so the mic does not stay open.
      if recordingState {
        onDiagnostic?(
          NativeDiagnostic(
            DiagnosticCode.tapDisabled,
            "event tap was disabled mid-dictation; stopping safely"))
        stopRecording()
      }
      return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // Esc cancels an in-flight dictation, in any mode (consume it so it does
    // not also trigger Esc behaviour in the focused app).
    if type == .keyDown && keyCode == kEscKeyCode && recordingState {
      cancelRecording()
      return nil
    }

    guard mode == .holdToTalk, UInt16(keyCode) == targetKeyCode else {
      return Unmanaged.passUnretained(event)
    }

    switch type {
    case .keyDown:
      if !recordingState && event.flags.contains(requiredFlags) {
        startRecording()
        return nil  // consume so ⌥Space etc. does not type into the app
      }
      // If we are recording this is a key-repeat of the held shortcut; consume.
      return recordingState ? nil : Unmanaged.passUnretained(event)
    case .keyUp:
      if recordingState {
        stopRecording()
        return nil
      }
      return Unmanaged.passUnretained(event)
    default:
      return Unmanaged.passUnretained(event)
    }
  }

  // MARK: - Recording lifecycle

  private var recordingState: Bool {
    stateLock.lock(); defer { stateLock.unlock() }
    return isRecording
  }

  private func startRecording() {
    stateLock.lock()
    if isRecording { stateLock.unlock(); return }
    isRecording = true
    stateLock.unlock()
    do {
      _ = try recorder.start()
      startWatchdog()
      onEvent?(.started)
    } catch {
      stateLock.lock(); isRecording = false; stateLock.unlock()
      RbLog.dictation.error("dictation start failed: \(error.localizedDescription)")
    }
  }

  private func stopRecording() {
    stateLock.lock()
    guard isRecording else { stateLock.unlock(); return }
    isRecording = false
    stateLock.unlock()
    stopWatchdog()
    let url = recorder.stop()
    if let url { onEvent?(.stopped(url.path)) }
  }

  private func cancelRecording() {
    stateLock.lock()
    guard isRecording else { stateLock.unlock(); return }
    isRecording = false
    stateLock.unlock()
    stopWatchdog()
    recorder.cancel()
    onEvent?(.cancelled)
  }

  private func startWatchdog() {
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
    timer.schedule(deadline: .now() + kMaxDictationSeconds)
    timer.setEventHandler { [weak self] in
      guard let self, self.recordingState else { return }
      RbLog.dictation.notice("dictation watchdog fired; force-stopping")
      self.onDiagnostic?(
        NativeDiagnostic(
          DiagnosticCode.dictationWatchdog,
          "dictation exceeded \(Int(kMaxDictationSeconds))s; stopped automatically"))
      self.stopRecording()
    }
    timer.resume()
    watchdog = timer
  }

  private func stopWatchdog() {
    watchdog?.cancel()
    watchdog = nil
  }

  // MARK: - Paste

  /// Pastes [text] into the frontmost app. The key events are built *before*
  /// the pasteboard is touched; the original pasteboard is restored after
  /// ~500 ms, but only if it was not changed in the meantime. The staged item
  /// is marked transient/concealed so clipboard managers ignore it. The paste
  /// is delayed until the shortcut modifiers are released and uses a private
  /// event source so it does not combine with physically-held keys.
  func pasteText(_ text: String) throws {
    guard AXIsProcessTrusted() else {
      throw RbNativeError.pasteFailed("Accessibility permission required to paste")
    }

    // 1. Build the key events first — fail before mutating the pasteboard.
    guard let source = CGEventSource(stateID: .privateState) else {
      throw RbNativeError.pasteFailed("cannot create event source")
    }
    let vKey = Self.resolveVKeyCode()
    guard
      let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
    else {
      throw RbNativeError.pasteFailed("cannot create key events")
    }
    down.flags = .maskCommand
    up.flags = .maskCommand

    // 2. Snapshot + stage the text (marked transient/concealed).
    let pasteboard = SystemPasteboard()
    let snapshot = PasteboardManager.snapshot(pasteboard)
    let changeCountAfterWrite = PasteboardManager.writeTransient(text, into: pasteboard)

    // 3. Paste once the shortcut modifiers are released; always restore.
    Self.whenModifiersReleased {
      down.post(tap: .cghidEventTap)
      up.post(tap: .cghidEventTap)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        PasteboardManager.restoreIfUnchanged(
          snapshot, into: pasteboard, expectedChangeCount: changeCountAfterWrite)
      }
    }
  }

  /// Invokes [action] on the main thread once the common shortcut modifiers are
  /// no longer physically held (or after a ~1s timeout), so a synthetic ⌘V is
  /// not polluted by a still-held Option/Control/Shift.
  private static func whenModifiersReleased(
    deadline: Date = Date().addingTimeInterval(1.0), _ action: @escaping () -> Void
  ) {
    let held: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
    let current = CGEventSource.flagsState(.combinedSessionState)
    if current.intersection(held).isEmpty || Date() >= deadline {
      DispatchQueue.main.async(execute: action)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
      whenModifiersReleased(deadline: deadline, action)
    }
  }

  /// Resolves the virtual key code that produces "v" on the current keyboard
  /// layout (for ⌘V), falling back to the ANSI code 9.
  static func resolveVKeyCode() -> UInt16 {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
      let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return kFallbackVKeyCode }
    let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data

    return layoutData.withUnsafeBytes { raw -> UInt16 in
      guard let keyLayout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
      else { return kFallbackVKeyCode }
      var deadKeyState: UInt32 = 0
      var chars = [UniChar](repeating: 0, count: 4)
      var length = 0
      for code in 0..<UInt16(128) {
        let status = UCKeyTranslate(
          keyLayout, code, UInt16(kUCKeyActionDown), 0,
          UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
          &deadKeyState, chars.count, &length, &chars)
        if status == noErr, length == 1, chars[0] == UniChar(UnicodeScalar("v").value) {
          return code
        }
      }
      return kFallbackVKeyCode
    }
  }

  // MARK: - Sounds

  /// Plays a start/end cue. Called by the app via `playDictationSound`; the
  /// plugin no longer plays sounds automatically on dictation start/stop.
  func playSound(_ sound: DictationSoundKind) {
    let name = sound == .start ? "Tink" : "Pop"
    NSSound(named: NSSound.Name(name))?.play()
  }

  // MARK: - Modifier mapping

  private static func carbonModifiers(_ modifiers: [String]) -> UInt32 {
    var flags: UInt32 = 0
    for modifier in modifiers {
      switch modifier {
      case "command": flags |= UInt32(cmdKey)
      case "option": flags |= UInt32(optionKey)
      case "control": flags |= UInt32(controlKey)
      case "shift": flags |= UInt32(shiftKey)
      default: break  // `function` is not supported by Carbon hotkeys
      }
    }
    return flags
  }

  private static func cgFlags(_ modifiers: [String]) -> CGEventFlags {
    var flags: CGEventFlags = []
    for modifier in modifiers {
      switch modifier {
      case "command": flags.insert(.maskCommand)
      case "option": flags.insert(.maskAlternate)
      case "control": flags.insert(.maskControl)
      case "shift": flags.insert(.maskShift)
      case "function": flags.insert(.maskSecondaryFn)
      default: break
      }
    }
    return flags
  }
}

/// Matches the Dart `DictationSound` enum.
enum DictationSoundKind: String {
  case start
  case end
}
