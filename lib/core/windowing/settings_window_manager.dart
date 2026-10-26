import 'package:flutter/foundation.dart';

/// A handle to a single native OS window.
///
/// This abstracts Flutter's experimental, `@internal` windowing API
/// (`WindowController` and friends) so the rest of the app depends only on this
/// small, stable seam. The production implementation lives in
/// `app_windows.dart` (the one place that touches the internal API); tests use
/// a fake. See https://github.com/flutter/flutter/issues/30701.
abstract class NativeWindow implements Listenable {
  /// Whether the underlying native window still exists.
  bool get isAlive;

  /// Brings the window to the front and gives it keyboard focus.
  void activate();

  /// Updates the native window title shown in the title bar.
  void setTitle(String title);

  /// Destroys the native window and releases its resources.
  void destroy();
}

/// Creates a native window titled [title].
///
/// [onCloseRequested] fires when the user tries to close the window (red
/// traffic light or ⌘W handled natively); the manager decides what to do.
typedef NativeWindowFactory =
    NativeWindow Function({
      required String title,
      required VoidCallback onCloseRequested,
    });

/// Owns the single Settings window instance.
///
/// This is pure app logic (no Flutter widgets, no platform calls) so the
/// open/focus/single-instance/close behaviour can be unit-tested with a fake
/// [NativeWindowFactory]. A widget host (the windowing `ViewCollection`)
/// listens to this and renders the real window when [window] is non-null.
class SettingsWindowManager extends ChangeNotifier {
  SettingsWindowManager({
    required NativeWindowFactory createWindow,
    required String Function() resolveInitialTitle,
  }) : _createWindow = createWindow,
       _resolveInitialTitle = resolveInitialTitle;

  final NativeWindowFactory _createWindow;
  final String Function() _resolveInitialTitle;

  NativeWindow? _window;

  /// The live window, or null when Settings is closed.
  NativeWindow? get window => _window;

  /// Whether the Settings window is currently open.
  bool get isOpen => _window != null;

  /// ⌘, — opens the Settings window, or focuses the existing one.
  ///
  /// Enforces a single instance: a second invocation never creates a second
  /// window, it just brings the current one forward.
  void openOrFocus() {
    final existing = _window;
    if (existing != null && existing.isAlive) {
      existing.activate();
      return;
    }
    _window = _createWindow(
      title: _resolveInitialTitle(),
      onCloseRequested: close,
    );
    notifyListeners();
  }

  /// ⌘W / red traffic light / logout — closes the window if open.
  void close() {
    final w = _window;
    if (w == null) return;
    _window = null;
    notifyListeners();
    if (w.isAlive) w.destroy();
  }

  /// Updates the native window title (the selected tab, e.g. "Geral").
  void setTitle(String title) => _window?.setTitle(title);

  @override
  void dispose() {
    final w = _window;
    _window = null;
    if (w != null && w.isAlive) w.destroy();
    super.dispose();
  }
}
