import Cocoa
import FlutterMacOS

// RbNotes runs its Flutter engine HEADLESS and multi-view: the main window and
// the Settings window are both created by Flutter's windowing API from Dart
// (see lib/core/windowing/app_windows.dart). There is deliberately no
// `MainFlutterWindow`/implicit view — a single-view engine aborts in
// `-[FlutterEngine enableMultiView]` when a second window is created. This
// mirrors the SDK's examples/multiple_windows setup.
@main
class AppDelegate: FlutterAppDelegate {
  private var engine: FlutterEngine?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let engine = FlutterEngine(name: "rbnotes", project: nil, allowHeadlessExecution: true)
    self.engine = engine
    engine.run(withEntrypoint: nil)
    RegisterGeneratedPlugins(registry: engine)
    RbNativeWindow.register(messenger: engine.binaryMessenger)
    super.applicationDidFinishLaunching(notification)
  }

  // Closing the last window quits the app (the previous `window_manager`
  // behaviour; there is no close-to-tray).
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Clicking the dock icon brings the (possibly minimized) windows forward.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    for window in sender.windows where window.isMiniaturized {
      window.deminiaturize(nil)
    }
    sender.activate(ignoringOtherApps: true)
    return true
  }
}
