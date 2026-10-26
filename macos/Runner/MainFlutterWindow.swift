import Cocoa
import FlutterMacOS

// Native window styling that Flutter's Dart windowing API cannot express.
// Reached from `lib/core/windowing/app_windows.dart` over the
// `rbnotes/native_window` channel, keyed by each window's NSWindow handle.
//
// NOTE: this file is named `MainFlutterWindow.swift` only because it is already
// referenced by the Xcode project. The app no longer uses a `MainFlutterWindow`
// (the engine runs headless/multi-view — see AppDelegate.swift); all windows
// come from Dart.
enum RbNativeWindow {
  /// Top-left inset for the native traffic lights on the main window, matching
  /// where the design placed the (formerly fake) dots in the sidebar header.
  private static let trafficLightInset = NSPoint(x: 20, y: 22)

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "rbnotes/native_window",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard let window = windowFromArguments(call.arguments) else {
        result(FlutterError(code: "bad_args", message: "missing window handle", details: nil))
        return
      }
      switch call.method {
      case "styleMainWindow":
        DispatchQueue.main.async { styleMainWindow(window) }
        result(nil)
      case "styleSettingsWindow":
        DispatchQueue.main.async { styleSettingsWindow(window) }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func windowFromArguments(_ arguments: Any?) -> NSWindow? {
    guard
      let args = arguments as? [String: Any],
      let handle = args["handle"] as? Int,
      handle != 0,
      let pointer = UnsafeRawPointer(bitPattern: handle)
    else { return nil }
    return Unmanaged<NSWindow>.fromOpaque(pointer).takeUnretainedValue()
  }

  // Main window: hidden/transparent title bar + full-size content, keeping the
  // NATIVE traffic lights but nudged to the design inset. Keep the native
  // behaviours (hover, inactive greying, double-click zoom, drag, fullscreen)
  // and DO NOT replace the window delegate (the windowing API uses it for close
  // callbacks) — reposition via notifications instead.
  private static func styleMainWindow(_ window: NSWindow) {
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.styleMask.insert(.fullSizeContentView)
    window.isMovableByWindowBackground = false
    positionTrafficLights(window)

    let center = NotificationCenter.default
    for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didExitFullScreenNotification] {
      center.addObserver(forName: name, object: window, queue: .main) { _ in
        positionTrafficLights(window)
      }
    }
  }

  private static func positionTrafficLights(_ window: NSWindow) {
    let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
      .compactMap { window.standardWindowButton($0) }
    guard let close = buttons.first, let titlebar = close.superview else { return }
    // Titlebar view is not flipped: y grows upward from the bottom.
    let targetX = trafficLightInset.x
    let targetY = titlebar.bounds.height - trafficLightInset.y - close.frame.height
    let dx = targetX - close.frame.origin.x
    let dy = targetY - close.frame.origin.y
    for button in buttons {
      button.setFrameOrigin(
        NSPoint(x: button.frame.origin.x + dx, y: button.frame.origin.y + dy)
      )
    }
  }

  // Settings window: like macOS System Settings — fixed size, no zoom/minimize,
  // centered. Keeps the standard title bar + traffic lights.
  private static func styleSettingsWindow(_ window: NSWindow) {
    window.styleMask.remove(.resizable)
    window.standardWindowButton(.zoomButton)?.isEnabled = false
    window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
    window.center()
  }
}
