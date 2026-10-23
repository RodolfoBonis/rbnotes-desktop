import AppKit
import SwiftUI

/// Drives the Dynamic-Island-style activity overlay: a non-activating `NSPanel`
/// hosting SwiftUI ([OverlayView]) that emerges from the notch (or drops from
/// the menu bar on notchless Macs) while the user records or dictates.
///
/// The panel never activates RbNotes (so dictation keeps pasting into the app
/// in focus), floats above full-screen apps on every Space, and draws its own
/// shadow. All AppKit work is confined to the main thread — the plugin
/// dispatches every call here onto main.
///
/// Pure geometry (`NotchGeometry`) and the state clamping/auto-hide rules
/// (`OverlayLogic`) live in `Core` and are unit-tested via `RbNativeCore`.
@available(macOS 13.0, *)
final class ActivityOverlayController {
  /// Emits a wire action name: `pause`/`resume`/`stop`/`discard`/`openApp`.
  var onAction: ((String) -> Void)?

  private var panel: NSPanel?
  private let model = OverlayViewModel()

  private var startedAt = Date()
  private var tickTimer: Timer?
  private var collapseWork: DispatchWorkItem?
  private var hideWork: DispatchWorkItem?
  private var hoverExitWork: DispatchWorkItem?

  // MARK: - Public API (main thread)

  func show(mode: OverlayMode, startedAt: Date) {
    cancelPendingHide()
    self.startedAt = startedAt
    model.mode = mode
    model.phase = .live
    model.paused = false
    model.pasted = false
    model.liveText = ""
    model.progress = 0
    model.message = ""
    model.levels = []
    model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    // Recording starts expanded; dictation is always its compact self.
    model.expanded = mode == .recording
    model.onAction = { [weak self] name in self?.onAction?(name) }
    model.onHover = { [weak self] hovering in self?.hoverChanged(hovering) }

    let screen = Self.menuBarScreen()
    let geom = NotchInfo(screen: screen)
    ensurePanel()
    guard let panel else { return }

    let target = targetFrame(on: screen, geom: geom)
    animateIn(panel: panel, from: geom.birthFrame, to: target)
    startTicking()
    scheduleInitialCollapse(mode: mode)
  }

  func update(
    micLevel: Double?, systemLevel: Double?, liveText: String?,
    phase: OverlayPhase?, progress: Double?, message: String?, paused: Bool?
  ) {
    guard panel != nil else { return }
    if micLevel != nil || systemLevel != nil {
      model.pushLevel(mic: micLevel ?? 0, system: systemLevel ?? 0)
    }
    if let liveText { model.liveText = liveText }
    if let progress { model.progress = OverlayLogic.clamp01(progress) }
    if let message { model.message = message }
    if let paused { model.paused = paused }
    if let phase {
      let previous = model.phase
      model.phase = phase
      if model.mode == .dictation, phase == .done { model.pasted = true }
      if phase != previous { phaseChanged(to: phase) }
    }
  }

  func hide(delayMs: Int) {
    let delay = max(0, Double(delayMs) / 1000)
    cancelPendingHide()
    let work = DispatchWorkItem { [weak self] in self?.animateOutAndClose() }
    hideWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  // MARK: - Panel lifecycle

  private func ensurePanel() {
    guard panel == nil else { return }
    let p = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 540, height: 170),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered, defer: false)
    p.isFloatingPanel = true
    p.becomesKeyOnlyIfNeeded = true
    p.hidesOnDeactivate = false
    p.level = .statusBar
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = false  // we draw our own diffuse shadow in SwiftUI
    p.isMovableByWindowBackground = false
    p.ignoresMouseEvents = false

    let host = NSHostingView(rootView: OverlayView(model: model))
    host.autoresizingMask = [.width, .height]
    host.frame = p.contentView?.bounds ?? .zero
    p.contentView = host
    panel = p
  }

  private func targetFrame(on screen: NSScreen, geom: NotchInfo) -> NSRect {
    let size = targetSize()
    let rect = NotchGeometry.pillFrame(
      screen: geom.screenRect, width: Double(size.width),
      height: Double(size.height), topInset: geom.topInset)
    return NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
  }

  /// The panel size for the current mode/phase/expansion.
  private func targetSize() -> CGSize {
    switch (model.mode, model.phase) {
    case (.dictation, _):
      return CGSize(width: model.pasted ? 160 : 260, height: 56)
    case (_, .processing):
      return CGSize(width: 420, height: 72)
    case (_, .done):
      return CGSize(width: 320, height: 56)
    case (_, .error):
      return CGSize(width: 400, height: 68)
    case (_, .live):
      return model.expanded
        ? CGSize(width: 540, height: 178)
        : CGSize(width: 320, height: 64)
    }
  }

  private func resizeToCurrentState(animated: Bool) {
    guard let panel else { return }
    let screen = Self.menuBarScreen()
    let geom = NotchInfo(screen: screen)
    let frame = targetFrame(on: screen, geom: geom)
    if animated && !model.reduceMotion {
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.28
        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animator().setFrame(frame, display: true)
      }
    } else {
      panel.setFrame(frame, display: true)
    }
  }

  private func animateIn(panel: NSPanel, from birth: NotchGeometry.Rect, to target: NSRect) {
    let birthRect = NSRect(x: birth.x, y: birth.y, width: birth.width, height: birth.height)
    panel.orderFrontRegardless()
    if model.reduceMotion {
      // Reduce Motion: no spring/scale, just a gentle fade at the final frame.
      panel.setFrame(target, display: true)
      panel.alphaValue = 0
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        panel.animator().alphaValue = 1
      }
      return
    }
    panel.alphaValue = 1
    panel.setFrame(birthRect, display: true)
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.35
      // Over-shooting ease approximates a spring growing out of the notch.
      ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.1)
      panel.animator().setFrame(target, display: true)
    }
  }

  private func animateOutAndClose() {
    guard let panel else { return }
    tickTimer?.invalidate()
    tickTimer = nil
    let screen = Self.menuBarScreen()
    let geom = NotchInfo(screen: screen)
    let birth = geom.birthFrame
    let birthRect = NSRect(x: birth.x, y: birth.y, width: birth.width, height: birth.height)
    if model.reduceMotion {
      NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.2
        panel.animator().alphaValue = 0
      }) { [weak self] in self?.teardown() }
      return
    }
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.28
      ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
      panel.animator().setFrame(birthRect, display: true)
      panel.animator().alphaValue = 0
    }) { [weak self] in self?.teardown() }
  }

  private func teardown() {
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
  }

  // MARK: - Timing

  private func startTicking() {
    tickTimer?.invalidate()
    model.elapsed = Date().timeIntervalSince(startedAt)
    let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      guard let self else { return }
      if !self.model.paused {
        self.model.elapsed = Date().timeIntervalSince(self.startedAt)
      } else {
        // Keep the displayed time frozen while paused by advancing startedAt.
        self.startedAt = Date().addingTimeInterval(-self.model.elapsed)
      }
    }
    RunLoop.main.add(t, forMode: .common)
    tickTimer = t
  }

  private func scheduleInitialCollapse(mode: OverlayMode) {
    collapseWork?.cancel()
    guard mode == .recording else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.model.phase == .live else { return }
      self.model.expanded = false
      self.resizeToCurrentState(animated: true)
    }
    collapseWork = work
    DispatchQueue.main.asyncAfter(
      deadline: .now() + OverlayLogic.initialExpandedWindow, execute: work)
  }

  private func phaseChanged(to phase: OverlayPhase) {
    collapseWork?.cancel()
    if phase == .live { model.expanded = model.mode == .recording }
    resizeToCurrentState(animated: true)
    if let delay = OverlayLogic.autoHideDelay(phase: phase) {
      hide(delayMs: Int(delay * 1000))
    }
  }

  private func hoverChanged(_ hovering: Bool) {
    guard model.mode == .recording, model.phase == .live else { return }
    hoverExitWork?.cancel()
    if hovering {
      collapseWork?.cancel()
      if !model.expanded {
        model.expanded = true
        resizeToCurrentState(animated: true)
      }
    } else {
      let work = DispatchWorkItem { [weak self] in
        guard let self, self.model.phase == .live else { return }
        self.model.expanded = false
        self.resizeToCurrentState(animated: true)
      }
      hoverExitWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
  }

  private func cancelPendingHide() {
    hideWork?.cancel()
    hideWork = nil
  }

  // MARK: - Screen / notch

  /// The screen that owns the menu bar. macOS guarantees `NSScreen.screens`
  /// starts with the menu-bar screen (origin at (0,0)); we fall back to
  /// `.main` and then any screen. Documented in the contract.
  static func menuBarScreen() -> NSScreen {
    NSScreen.screens.first ?? NSScreen.main ?? NSScreen.screens[0]
  }
}

/// Resolved notch/menu-bar metrics for a screen, in AppKit screen coordinates.
@available(macOS 13.0, *)
private struct NotchInfo {
  let screenRect: NotchGeometry.Rect
  let notchWidth: Double
  let notchHeight: Double
  /// 0 on notched Macs (pill hugs the top edge); menu-bar height otherwise.
  let topInset: Double

  init(screen: NSScreen) {
    let f = screen.frame
    screenRect = NotchGeometry.Rect(
      x: Double(f.origin.x), y: Double(f.origin.y),
      width: Double(f.width), height: Double(f.height))

    let insetTop = Double(screen.safeAreaInsets.top)
    var width = 0.0
    if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
      width = Double(f.width - left.width - right.width)
    }
    notchHeight = insetTop
    notchWidth = width
    topInset = NotchGeometry.hasNotch(notchHeight: insetTop)
      ? 0 : Double(NSStatusBar.system.thickness)
  }

  var birthFrame: NotchGeometry.Rect {
    NotchGeometry.birthFrame(
      screen: screenRect, notchWidth: notchWidth, notchHeight: notchHeight,
      topInset: topInset)
  }
}
