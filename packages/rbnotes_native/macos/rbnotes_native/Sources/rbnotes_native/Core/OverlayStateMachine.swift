import Foundation

/// Which activity the overlay represents (mirrors the Dart `OverlayMode`).
public enum OverlayMode: String {
  case recording
  case dictation
}

/// The visual phase of the overlay (mirrors the Dart `OverlayPhase`).
public enum OverlayPhase: String {
  case live
  case processing
  case done
  case error
}

/// Pure, Foundation-only model of the overlay's content and the derived
/// presentation decisions (expanded vs compact, auto-hide timing).
///
/// The AppKit/SwiftUI layer owns the actual panel and timers; it feeds user
/// updates into [apply] and reads back the resulting [OverlayState] plus the
/// timing helpers. Keeping this logic here makes the state transitions unit
/// testable via `RbNativeCore`.
public struct OverlayState: Equatable {
  public var mode: OverlayMode
  public var phase: OverlayPhase
  public var paused: Bool
  public var micLevel: Double
  public var systemLevel: Double
  public var liveText: String
  public var progress: Double
  public var message: String

  public init(
    mode: OverlayMode,
    phase: OverlayPhase = .live,
    paused: Bool = false,
    micLevel: Double = 0,
    systemLevel: Double = 0,
    liveText: String = "",
    progress: Double = 0,
    message: String = ""
  ) {
    self.mode = mode
    self.phase = phase
    self.paused = paused
    self.micLevel = micLevel
    self.systemLevel = systemLevel
    self.liveText = liveText
    self.progress = progress
    self.message = message
  }
}

/// A partial update coming from `updateActivityOverlay` (every field optional).
public struct OverlayUpdate {
  public var micLevel: Double?
  public var systemLevel: Double?
  public var liveText: String?
  public var phase: OverlayPhase?
  public var progress: Double?
  public var message: String?
  public var paused: Bool?

  public init(
    micLevel: Double? = nil,
    systemLevel: Double? = nil,
    liveText: String? = nil,
    phase: OverlayPhase? = nil,
    progress: Double? = nil,
    message: String? = nil,
    paused: Bool? = nil
  ) {
    self.micLevel = micLevel
    self.systemLevel = systemLevel
    self.liveText = liveText
    self.phase = phase
    self.progress = progress
    self.message = message
    self.paused = paused
  }
}

public enum OverlayLogic {
  /// How long, after show, the recording HUD stays expanded by default before
  /// collapsing to the compact pill (unless the mouse is hovering it).
  public static let initialExpandedWindow: TimeInterval = 2.0

  /// How long the "done" state lingers before the overlay auto-hides. `nil`
  /// means "do not auto-hide" (live/processing stay until told otherwise;
  /// errors persist so the user can read them).
  public static func autoHideDelay(phase: OverlayPhase) -> TimeInterval? {
    switch phase {
    case .done: return 1.5
    case .live, .processing, .error: return nil
    }
  }

  /// Clamps a 0..1 level/progress value, tolerating NaN and out-of-range input
  /// from the wire so the renderer never sees a bad number.
  public static func clamp01(_ value: Double) -> Double {
    if value.isNaN { return 0 }
    return min(1, max(0, value))
  }

  /// Applies a partial [update] onto [state], clamping numeric fields and
  /// leaving untouched every field the update did not set.
  public static func apply(_ update: OverlayUpdate, to state: OverlayState) -> OverlayState {
    var next = state
    if let v = update.micLevel { next.micLevel = clamp01(v) }
    if let v = update.systemLevel { next.systemLevel = clamp01(v) }
    if let v = update.liveText { next.liveText = v }
    if let v = update.phase { next.phase = v }
    if let v = update.progress { next.progress = clamp01(v) }
    if let v = update.message { next.message = v }
    if let v = update.paused { next.paused = v }
    return next
  }
}
