import AppKit
import ApplicationServices
import CoreAudio
import Foundation

/// Detects when the user is likely in a meeting (Phase 3, option F) so the app
/// can offer "Record this meeting?".
///
/// Signal = another process is using the default input device
/// (`kAudioDevicePropertyDeviceIsRunningSomewhere`, re-bound when the default
/// input changes) **and** the foreground app is a conferencing app (Zoom,
/// Teams, Webex, FaceTime, Slack) or a browser hosting a meeting (confirmed by
/// the tab title via Accessibility when available, otherwise assumed from the
/// browser + mic-in-use). RbNotes' own microphone use is ignored.
///
/// Transitions are debounced (~3 s) and reported as a start event
/// (`micInUse == true`) and an end event (`micInUse == false`) via `onSignal`.
///
/// All state is confined to the **main thread**: `setEnabled` hops to main, the
/// CoreAudio listener blocks are delivered on the main queue, and the debounce
/// uses a main-queue work item. This avoids any cross-queue locking/deadlock.
final class MeetingDetector {
  /// Called on the main thread with `(app, micInUse, startedAt)`.
  var onSignal: ((String, Bool, Date) -> Void)?
  /// Returns true while RbNotes itself is capturing the mic, so its own use is
  /// not mistaken for a meeting. Called on the main thread.
  var isSelfUsingMic: (() -> Bool)?

  private let debounce: TimeInterval
  private var enabled = false

  // CoreAudio state.
  private var inputDevice = AudioObjectID(kAudioObjectUnknown)
  private var runningListener: AudioObjectPropertyListenerBlock?
  private var defaultListener: AudioObjectPropertyListenerBlock?

  // Meeting state.
  private var active = false
  private var activeApp = ""
  private var startedAt: Date?
  private var pending: DispatchWorkItem?

  init(debounce: TimeInterval = 3.0) {
    self.debounce = debounce
  }

  func setEnabled(_ on: Bool) {
    onMain { [weak self] in
      guard let self else { return }
      if on {
        guard !self.enabled else { return }
        self.enabled = true
        self.bindDefaultInputListener()
        self.rebindRunningListener()
        self.evaluate()
      } else {
        guard self.enabled else { return }
        self.enabled = false
        self.unbindAll()
        self.pending?.cancel()
        self.pending = nil
        if self.active, let started = self.startedAt {
          let app = self.activeApp
          self.active = false
          self.emit(app: app, inUse: false, started: started)
        }
        self.startedAt = nil
      }
    }
  }

  deinit {
    // Property removal is safe from any thread; blocks were scheduled on main.
    unbindAll()
  }

  private func onMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
  }

  // MARK: - CoreAudio listeners (main)

  private func bindDefaultInputListener() {
    var address = Self.defaultInputAddress
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.onMain { self?.rebindRunningListener(); self?.evaluate() }
    }
    defaultListener = block
    AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
  }

  private func rebindRunningListener() {
    if inputDevice != kAudioObjectUnknown, let old = runningListener {
      var running = Self.runningAddress
      AudioObjectRemovePropertyListenerBlock(inputDevice, &running, DispatchQueue.main, old)
      runningListener = nil
    }
    inputDevice = Self.defaultInputDevice()
    guard inputDevice != kAudioObjectUnknown else { return }
    var running = Self.runningAddress
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.onMain { self?.evaluate() }
    }
    runningListener = block
    AudioObjectAddPropertyListenerBlock(inputDevice, &running, DispatchQueue.main, block)
  }

  private func unbindAll() {
    if inputDevice != kAudioObjectUnknown, let old = runningListener {
      var running = Self.runningAddress
      AudioObjectRemovePropertyListenerBlock(inputDevice, &running, DispatchQueue.main, old)
    }
    runningListener = nil
    if let old = defaultListener {
      var address = Self.defaultInputAddress
      AudioObjectRemovePropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, old)
    }
    defaultListener = nil
    inputDevice = kAudioObjectUnknown
  }

  // MARK: - Evaluation (main)

  private func evaluate() {
    guard enabled else { return }
    let micRunning = Self.isRunningSomewhere(inputDevice)
    let selfUsing = isSelfUsingMic?() ?? false
    let othersUsing = micRunning && !selfUsing
    let app = Self.currentMeetingApp()
    let isMeeting = othersUsing && app != nil
    let appName = app ?? activeApp

    pending?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.commit(isMeeting: isMeeting, app: appName)
    }
    pending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
  }

  private func commit(isMeeting: Bool, app: String) {
    guard enabled else { return }
    if isMeeting, !active {
      active = true
      activeApp = app
      let started = Date()
      startedAt = started
      emit(app: app, inUse: true, started: started)
    } else if !isMeeting, active {
      active = false
      let started = startedAt ?? Date()
      emit(app: activeApp, inUse: false, started: started)
      startedAt = nil
    }
  }

  private func emit(app: String, inUse: Bool, started: Date) {
    RbLog.meeting.info(
      "meeting signal app=\(app, privacy: .public) inUse=\(inUse, privacy: .public)")
    onSignal?(app, inUse, started)
  }

  // MARK: - CoreAudio helpers

  private static var defaultInputAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)

  private static var runningAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)

  static func defaultInputDevice() -> AudioObjectID {
    var deviceId = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = defaultInputAddress
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceId)
    return status == noErr ? deviceId : AudioObjectID(kAudioObjectUnknown)
  }

  static func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
    guard device != kAudioObjectUnknown else { return false }
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = runningAddress
    let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
    return status == noErr && value != 0
  }

  // MARK: - Foreground app (main)

  /// The meeting app name for the frontmost app, or nil when it is not a
  /// meeting. Browsers are confirmed by the focused-window title via
  /// Accessibility; when AX is unavailable the browser + mic-in-use is taken as
  /// a meeting (contract: "use the tab title if available, otherwise just the
  /// app name").
  static func currentMeetingApp() -> String? {
    guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
    let kind = MeetingHeuristics.classify(bundleId: frontApp.bundleIdentifier)
    switch kind {
    case .conferencing(let app):
      return app
    case .browser(let app):
      guard AXIsProcessTrusted() else { return app }
      guard let title = focusedWindowTitle(pid: frontApp.processIdentifier) else {
        return app  // AX trusted but no readable title → assume a meeting.
      }
      return MeetingHeuristics.titleLooksLikeMeeting(title) ? app : nil
    case .other:
      return nil
    }
  }

  static func focusedWindowTitle(pid: pid_t) -> String? {
    let appElement = AXUIElementCreateApplication(pid)
    var windowRef: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
      let windowValue = windowRef,
      CFGetTypeID(windowValue) == AXUIElementGetTypeID()
    else { return nil }
    let windowElement = windowValue as! AXUIElement
    var titleRef: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        windowElement, kAXTitleAttribute as CFString, &titleRef) == .success,
      let title = titleRef as? String
    else { return nil }
    return title
  }
}
