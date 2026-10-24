import AppKit
import Carbon.HIToolbox
import Foundation

/// System-wide hotkeys identified by a string id, generalizing the dictation
/// hotkey registration to arbitrary shortcuts (e.g. "record a note from any
/// app"). Each id maps to a distinct Carbon `EventHotKeyID`, so a single
/// installed handler can route a press back to the right id.
///
/// Carbon (`RegisterEventHotKey`) is used — like the dictation *toggle* mode —
/// so no Accessibility permission is required and the shortcut is consumed by
/// the system (it will not type into the focused app).
///
/// All Carbon APIs must be touched on the main thread; the plugin dispatches
/// `register`/`unregister`/`unregisterAll` on main and the installed handler
/// runs on the main run loop, so no additional locking is needed.
final class GlobalHotkeyManager {
  private struct Entry {
    let hotKeyID: UInt32
    let ref: EventHotKeyRef
    let combo: HotkeyCombo
  }

  /// Carbon signature for global (non-dictation) hotkeys: 'RBGH'.
  private static let signature = OSType(0x5242_4748)

  private var entries: [String: Entry] = [:]
  private var nextHotKeyID: UInt32 = 1
  private var eventHandlerRef: EventHandlerRef?

  /// Set by the plugin to forward a press (the id) to the EventChannel.
  var onPressed: ((String) -> Void)?

  /// Set by the plugin so a requested hotkey that collides with the currently
  /// registered dictation hotkey is rejected with `hotkey_conflict`.
  var dictationCombo: (() -> HotkeyCombo?)?

  // MARK: - Registration

  /// Registers (or re-binds) the hotkey for [id].
  ///
  /// Throws `RbNativeError.hotkeyConflict` when the combo collides with the
  /// dictation hotkey, with another id's global hotkey, or when the system
  /// rejects `RegisterEventHotKey`.
  func register(id: String, keyCode: Int, modifiers: [String]) throws {
    let combo = HotkeyCombo(keyCode: keyCode, modifiers: Set(modifiers))

    if let dictation = dictationCombo?(), combo.conflicts(with: dictation) {
      throw RbNativeError.hotkeyConflict(
        "hotkey is already used by the dictation shortcut")
    }
    for (otherId, entry) in entries where otherId != id {
      if combo.conflicts(with: entry.combo) {
        throw RbNativeError.hotkeyConflict(
          "hotkey is already registered for '\(otherId)'")
      }
    }

    // Re-binding the same id: drop the old Carbon registration first so we do
    // not leak a hot key ref if the new registration fails.
    unregister(id)
    try ensureHandler()

    let hotKeyID = nextHotKeyID
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      UInt32(keyCode), Self.carbonModifiers(combo.carbonModifiers),
      EventHotKeyID(signature: Self.signature, id: hotKeyID),
      GetApplicationEventTarget(), 0, &ref)
    guard status == noErr, let ref else {
      throw RbNativeError.hotkeyConflict("RegisterEventHotKey failed (\(status))")
    }
    nextHotKeyID += 1
    entries[id] = Entry(hotKeyID: hotKeyID, ref: ref, combo: combo)
    RbLog.dictation.info("global hotkey registered (id=\(id, privacy: .public))")
  }

  /// Unregisters [id]. No-op if it is not registered.
  func unregister(_ id: String) {
    guard let entry = entries.removeValue(forKey: id) else { return }
    UnregisterEventHotKey(entry.ref)
  }

  /// Unregisters every global hotkey and removes the shared Carbon handler.
  func unregisterAll() {
    for entry in entries.values { UnregisterEventHotKey(entry.ref) }
    entries.removeAll()
    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
      self.eventHandlerRef = nil
    }
  }

  // MARK: - Carbon handler

  private func ensureHandler() throws {
    guard eventHandlerRef == nil else { return }
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData -> OSStatus in
        guard let userData, let event else { return OSStatus(eventNotHandledErr) }
        let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData)
          .takeUnretainedValue()
        return manager.handle(event: event)
      },
      1, &eventType, selfPtr, &eventHandlerRef)
    guard status == noErr else {
      throw RbNativeError.hotkeyConflict("InstallEventHandler failed (\(status))")
    }
  }

  /// Routes a Carbon hot-key event to the matching id. Returns
  /// `eventNotHandledErr` for anyone else's hotkey so other installed handlers
  /// (e.g. the dictation toggle) still get a chance to handle it.
  private func handle(event: EventRef) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
      event, EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID), nil,
      MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr, hotKeyID.signature == Self.signature else {
      return OSStatus(eventNotHandledErr)
    }
    guard let id = entries.first(where: { $0.value.hotKeyID == hotKeyID.id })?.key
    else {
      return OSStatus(eventNotHandledErr)
    }
    onPressed?(id)
    return noErr
  }

  // MARK: - Modifier mapping

  private static func carbonModifiers(_ modifiers: Set<String>) -> UInt32 {
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
}
