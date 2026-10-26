/// A tiny seam over the main application window, so app code (recording
/// overlay, "nota pronta" notifications, meeting suggestions, the tray) can ask
/// whether the window is focused and bring it forward without depending on the
/// `@internal` windowing API (or, previously, `window_manager`).
///
/// The production implementation wraps the main `WindowController`
/// (see `app_windows.dart`); tests use a fake.
abstract class MainWindowHandle {
  /// Whether the main window is currently focused/active (foreground).
  bool get isActive;

  /// Brings the main window to the front and focuses it (tray "Abrir RbNotes",
  /// the global record hotkey, dock reopen, etc.).
  void activate();
}
