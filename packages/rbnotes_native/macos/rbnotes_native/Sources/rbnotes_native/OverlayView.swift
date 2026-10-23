import Combine
import SwiftUI

/// Observable presentation state for the notch overlay. The controller writes
/// into it from the main thread; the SwiftUI [OverlayView] renders it.
///
/// It owns only presentation state: the pure transitions/clamping live in
/// `OverlayLogic`/`OverlayState` (unit-tested in `RbNativeCore`).
@available(macOS 13.0, *)
final class OverlayViewModel: ObservableObject {
  @Published var mode: OverlayMode = .recording
  @Published var phase: OverlayPhase = .live
  @Published var paused = false
  @Published var expanded = true
  @Published var elapsed: TimeInterval = 0
  @Published var liveText = ""
  @Published var progress: Double = 0
  @Published var message = ""
  /// Rolling window of recent audio levels (0..1), oldest first, for the bars.
  @Published var levels: [CGFloat] = []
  /// When true (Reduce Motion), transitions fade instead of springing/pulsing.
  @Published var reduceMotion = false
  /// True while the dictation pill is showing the "Colado" confirmation.
  @Published var pasted = false

  /// Called with a wire action name (`pause`/`resume`/`stop`/`discard`/`openApp`).
  var onAction: ((String) -> Void)?

  /// Called when the pointer enters (true) or leaves (false) the pill, so the
  /// controller can expand/collapse the recording HUD.
  var onHover: ((Bool) -> Void)?

  /// Number of waveform bars shown when expanded.
  static let maxBars = 48

  func pushLevel(mic: Double, system: Double) {
    let v = CGFloat(min(1, max(0, max(mic, system))))
    var next = levels
    next.append(v)
    if next.count > Self.maxBars {
      next.removeFirst(next.count - Self.maxBars)
    }
    levels = next
  }

  func act(_ name: String) { onAction?(name) }
}

@available(macOS 13.0, *)
private enum OverlayStyle {
  static let pill = Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255)
  static let accent = Color(red: 0xE0 / 255, green: 0x51 / 255, blue: 0x2E / 255)
  static let recRed = Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255)
  static let paused = Color(red: 0xFE / 255, green: 0xBC / 255, blue: 0x2E / 255)
  static let corner: CGFloat = 20
}

/// The SwiftUI content of the overlay panel.
@available(macOS 13.0, *)
struct OverlayView: View {
  @ObservedObject var model: OverlayViewModel

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: OverlayStyle.corner, style: .continuous)
        .fill(OverlayStyle.pill.opacity(0.96))
        .background(
          RoundedRectangle(cornerRadius: OverlayStyle.corner, style: .continuous)
            .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 16)

      content
        .padding(.horizontal, model.mode == .dictation ? 16 : 18)
        .padding(.vertical, model.mode == .dictation ? 12 : 16)
    }
    // Clicking the body (outside the explicit buttons) opens the app.
    .contentShape(RoundedRectangle(cornerRadius: OverlayStyle.corner))
    .onTapGesture { model.act("openApp") }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder private var content: some View {
    switch (model.mode, model.phase) {
    case (.dictation, _):
      dictationBody
    case (_, .processing):
      processingBody
    case (_, .done):
      doneBody
    case (_, .error):
      errorBody
    case (_, .live):
      recordingBody
    }
  }

  // MARK: - Recording

  private var recordingBody: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        RecDot(paused: model.paused, reduceMotion: model.reduceMotion)
        Text(model.paused ? "Pausado" : "Gravando")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white.opacity(0.85))
        Spacer()
        Text(timeString(model.elapsed))
          .font(.system(size: 20, weight: .medium).monospacedDigit())
      }
      OverlayWaveform(levels: model.levels, compact: !model.expanded)
        .frame(height: model.expanded ? 40 : 18)
      if model.expanded {
        LiveTranscriptView(text: model.liveText)
          .frame(height: 60)
        HStack(spacing: 8) {
          Text("Transcrevendo ao vivo no seu Mac")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.5))
          Spacer()
          PillButton(title: "Descartar", kind: .ghost) { model.act("discard") }
          PillButton(
            title: model.paused ? "Retomar" : "Pausar", kind: .soft
          ) { model.act(model.paused ? "resume" : "pause") }
          PillButton(title: "Concluir", kind: .finish) { model.act("stop") }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onHover { model.onHover?($0) }
  }

  // MARK: - Dictation

  private var dictationBody: some View {
    HStack(spacing: 12) {
      if model.pasted {
        Image(systemName: "checkmark")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(OverlayStyle.accent)
        Text("Colado")
          .font(.system(size: 13, weight: .semibold))
      } else {
        OverlayWaveform(levels: model.levels, compact: true)
          .frame(width: 120, height: 18)
        VStack(alignment: .leading, spacing: 2) {
          Text("Ditando…")
            .font(.system(size: 13, weight: .semibold))
          Text("solte ⌥Espaço para colar")
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.5))
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Processing / Done / Error

  private var processingBody: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(model.message.isEmpty ? "Preparando sua nota" : model.message)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.7))
      ProgressView(value: model.progress)
        .tint(OverlayStyle.accent)
        .frame(height: 3)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var doneBody: some View {
    HStack(spacing: 10) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 16))
        .foregroundStyle(OverlayStyle.accent)
      Text(model.message.isEmpty ? "Pronto" : model.message)
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var errorBody: some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 15))
        .foregroundStyle(OverlayStyle.recRed)
      Text(model.message.isEmpty ? "Algo deu errado" : model.message)
        .font(.system(size: 13, weight: .medium))
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func timeString(_ t: TimeInterval) -> String {
    let total = Int(t.rounded(.down))
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
  }
}

@available(macOS 13.0, *)
private struct RecDot: View {
  let paused: Bool
  let reduceMotion: Bool
  @State private var on = true

  var body: some View {
    Circle()
      .fill(paused ? OverlayStyle.paused : OverlayStyle.recRed)
      .frame(width: 9, height: 9)
      .opacity(paused || reduceMotion ? 1 : (on ? 1 : 0.35))
      .animation(
        paused || reduceMotion
          ? nil
          : .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
        value: on
      )
      .onAppear { if !paused && !reduceMotion { on.toggle() } }
  }
}

@available(macOS 13.0, *)
private struct OverlayWaveform: View {
  let levels: [CGFloat]
  let compact: Bool

  var body: some View {
    GeometryReader { geo in
      let count = max(levels.count, 1)
      let spacing: CGFloat = 2
      let barWidth: CGFloat = 3
      HStack(alignment: .center, spacing: spacing) {
        ForEach(0..<displayCount(for: geo.size.width), id: \.self) { i in
          let level = levelAt(i, visible: displayCount(for: geo.size.width))
          Capsule()
            .fill(Color.white.opacity(compact ? 0.55 : 0.85))
            .frame(
              width: barWidth,
              height: max(3, level * geo.size.height))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      .animation(.linear(duration: 0.08), value: levels)
      let _ = count
    }
  }

  private func displayCount(for width: CGFloat) -> Int {
    let per: CGFloat = 5  // 3pt bar + 2pt gap
    return max(8, min(OverlayViewModel.maxBars, Int(width / per)))
  }

  /// Right-aligns the newest samples, padding the left with small values.
  private func levelAt(_ index: Int, visible: Int) -> CGFloat {
    let offset = visible - levels.count
    let srcIndex = index - offset
    guard srcIndex >= 0, srcIndex < levels.count else { return 0.08 }
    return max(0.08, levels[srcIndex])
  }
}

@available(macOS 13.0, *)
private struct LiveTranscriptView: View {
  let text: String

  var body: some View {
    VStack(alignment: .leading) {
      Spacer(minLength: 0)
      Text(text)
        .font(.system(size: 14))
        .lineSpacing(3)
        .foregroundStyle(.white.opacity(0.9))
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
        .animation(.easeIn(duration: 0.25), value: text)
    }
    .mask(
      LinearGradient(
        colors: [.clear, .black],
        startPoint: .top, endPoint: .init(x: 0.5, y: 0.45))
    )
  }
}

@available(macOS 13.0, *)
private struct PillButton: View {
  enum Kind { case ghost, soft, finish }
  let title: String
  let kind: Kind
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        if kind == .finish {
          RoundedRectangle(cornerRadius: 2)
            .fill(OverlayStyle.accent)
            .frame(width: 9, height: 9)
        }
        Text(title)
          .font(.system(size: 12.5, weight: kind == .finish ? .semibold : .medium))
      }
      .padding(.horizontal, kind == .ghost ? 12 : 14)
      .frame(height: 30)
      .foregroundStyle(foreground)
      .background(background)
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }

  private var foreground: Color {
    switch kind {
    case .finish: return OverlayStyle.pill
    case .soft: return .white
    case .ghost: return .white.opacity(0.75)
    }
  }

  private var background: Color {
    switch kind {
    case .finish: return .white
    case .soft: return .white.opacity(hovering ? 0.2 : 0.12)
    case .ghost: return .white.opacity(hovering ? 0.08 : 0)
    }
  }
}
