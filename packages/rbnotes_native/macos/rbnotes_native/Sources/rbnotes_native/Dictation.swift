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
private let kVKeyCode: UInt16 = 9

/// Global dictation: a Carbon hotkey (toggle) or a CGEventTap (hold-to-talk),
/// an Esc-to-cancel tap, temporary mic recording, text pasting and sounds.
///
/// Requires Accessibility permission (event tap + synthetic ⌘V).
final class DictationManager {
  private var mode: DictationModeKind = .toggle
  private var targetKeyCode: UInt16 = 0
  private var requiredFlags: CGEventFlags = []

  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  private let recorder = DictationRecorder()
  private var isRecording = false
  private let stateLock = NSLock()

  /// Set by the plugin to forward events to the EventChannel.
  var onEvent: ((DictationEventKind) -> Void)?

  // MARK: - Registration

  func register(keyCode: Int, modifiers: [String], mode: DictationModeKind) throws {
    unregister()
    self.mode = mode
    self.targetKeyCode = UInt16(keyCode)
    self.requiredFlags = Self.cgFlags(modifiers)

    switch mode {
    case .toggle:
      try registerCarbonHotKey(keyCode: keyCode, modifiers: modifiers)
    case .holdToTalk:
      break  // handled entirely by the event tap
    }
    // Event tap: hold-to-talk key transitions and Esc-to-cancel in both modes.
    try installEventTap()
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
      { _, _, userData -> OSStatus in
        guard let userData else { return noErr }
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
      throw RbNativeError.hotkeyConflict("RegisterEventHotKey failed (\(status))")
    }
  }

  private func handleToggle() {
    if recordingState { stopRecording() } else { startRecording() }
  }

  // MARK: - Event tap

  private func installEventTap() throws {
    let mask =
      (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
        eventsOfInterest: CGEventMask(mask),
        callback: { _, type, event, userData -> Unmanaged<CGEvent>? in
          if let userData {
            let manager = Unmanaged<DictationManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handleTap(type: type, event: event)
          }
          return Unmanaged.passUnretained(event)
        },
        userInfo: selfPtr)
    else {
      throw RbNativeError.hotkeyConflict(
        "CGEventTapCreate failed — Accessibility permission required")
    }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    self.eventTap = tap
    self.runLoopSource = source
  }

  private func handleTap(type: CGEventType, event: CGEvent) {
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // Esc cancels an in-flight dictation, in any mode.
    if type == .keyDown && keyCode == kEscKeyCode && recordingState {
      cancelRecording()
      return
    }

    guard mode == .holdToTalk, UInt16(keyCode) == targetKeyCode else { return }

    switch type {
    case .keyDown:
      if !recordingState && event.flags.contains(requiredFlags) {
        startRecording()
      }
    case .keyUp:
      if recordingState { stopRecording() }
    default:
      break
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
      playSound(.start)
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
    let url = recorder.stop()
    playSound(.end)
    if let url { onEvent?(.stopped(url.path)) }
  }

  private func cancelRecording() {
    stateLock.lock()
    guard isRecording else { stateLock.unlock(); return }
    isRecording = false
    stateLock.unlock()
    recorder.cancel()
    onEvent?(.cancelled)
  }

  // MARK: - Paste

  /// Pastes [text] by saving the pasteboard, writing the string, synthesizing
  /// ⌘V and restoring the pasteboard after ~300 ms.
  func pasteText(_ text: String) throws {
    guard AXIsProcessTrusted() else {
      throw RbNativeError.pasteFailed("Accessibility permission required to paste")
    }
    let pasteboard = NSPasteboard.general
    let saved = Self.snapshot(pasteboard)

    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)

    guard let source = CGEventSource(stateID: .combinedSessionState) else {
      throw RbNativeError.pasteFailed("cannot create event source")
    }
    guard
      let down = CGEvent(keyboardEventSource: source, virtualKey: kVKeyCode, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: kVKeyCode, keyDown: false)
    else {
      throw RbNativeError.pasteFailed("cannot create key events")
    }
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      Self.restore(saved, to: pasteboard)
    }
  }

  // MARK: - Sounds

  func playSound(_ sound: DictationSoundKind) {
    let name = sound == .start ? "Tink" : "Pop"
    NSSound(named: NSSound.Name(name))?.play()
  }

  // MARK: - Pasteboard snapshot

  private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
    guard let items = pasteboard.pasteboardItems else { return [] }
    return items.map { item in
      var dict: [NSPasteboard.PasteboardType: Data] = [:]
      for type in item.types {
        if let data = item.data(forType: type) { dict[type] = data }
      }
      return dict
    }
  }

  private static func restore(
    _ snapshot: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard
  ) {
    pasteboard.clearContents()
    guard !snapshot.isEmpty else { return }
    let items = snapshot.map { dict -> NSPasteboardItem in
      let item = NSPasteboardItem()
      for (type, data) in dict { item.setData(data, forType: type) }
      return item
    }
    pasteboard.writeObjects(items)
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
