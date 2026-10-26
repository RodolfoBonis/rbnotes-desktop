// The ONE place that depends on Flutter's experimental, @internal windowing
// API (RegularWindowController & friends, exposed here as `WindowController`).
// Everything else talks to the stable [SettingsWindowManager] / [NativeWindow]
// / [MainWindowHandle] seams. The API is breaking even across patch releases,
// so if it changes this is the only file to touch.
//
// On macOS the engine must be created headless and multi-view (see
// AppDelegate.swift — no MainFlutterWindow), so BOTH the main window and the
// Settings window come from here. A single-view engine (the old
// `window_manager` setup) aborts in `-[FlutterEngine enableMultiView]` when a
// second window is created. See flutter/flutter#30701 and
// examples/multiple_windows.
//
// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_macos.dart'
    show BaseWindowControllerMacOS;
import 'package:flutter/widgets.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/core/windowing/main_window.dart';
import 'package:rbnotes/core/windowing/settings_window_manager.dart';

/// Native tweaks the Dart windowing API cannot express, applied in the Runner
/// against the NSWindow reached through each window's handle:
///  * the main window: hidden/transparent title bar, full-size content and the
///    native traffic lights inset to the design position;
///  * the Settings window: fixed size, no zoom/minimize, centered.
const _nativeWindowChannel = MethodChannel('rbnotes/native_window');

/// Initial size of the main window (was the `window_manager` WindowOptions).
const _mainWindowSize = Size(1280, 800);

/// Content size of the Settings window (matches the old modal).
const _settingsWindowSize = Size(700, 580);

/// Runs the app as a multi-window application: the main window plus a Settings
/// window that comes and goes with [settingsManager]. Registers a
/// [MainWindowHandle] in DI so app code can focus/query the main window.
void runRbNotesWindows({
  required Widget mainApp,
  required SettingsWindowManager settingsManager,
  required WidgetBuilder settingsBuilder,
}) {
  final mainController = WindowController(
    size: _mainWindowSize,
    constraints: const BoxConstraints(minWidth: 1040, minHeight: 680),
    title: 'RbNotes',
  );
  if (!di.isRegistered<MainWindowHandle>()) {
    di.registerSingleton<MainWindowHandle>(
      _MainWindowAdapter(mainController),
    );
  }
  _styleWindow('styleMainWindow', mainController);

  runWidget(
    _RbNotesWindows(
      mainController: mainController,
      mainApp: mainApp,
      settingsManager: settingsManager,
      settingsBuilder: settingsBuilder,
    ),
  );
}

/// The [NativeWindowFactory] wired into the production [SettingsWindowManager].
NativeWindow createSettingsNativeWindow({
  required String title,
  required VoidCallback onCloseRequested,
}) => _RegularWindowAdapter(title: title, onCloseRequested: onCloseRequested);

/// Reaches the NSWindow handle and asks the Runner to apply native styling.
void _styleWindow(String method, WindowController controller) {
  if (controller is! BaseWindowControllerMacOS) return;
  final handle = (controller as BaseWindowControllerMacOS).windowHandle;
  unawaited(_invokeStyle(method, handle.address));
}

Future<void> _invokeStyle(String method, int handleAddress) async {
  try {
    await _nativeWindowChannel.invokeMethod<void>(method, {
      'handle': handleAddress,
    });
  } on Object catch (e, st) {
    // Non-fatal: the window still works, it just keeps default affordances.
    await AppLogger.error(e, st, reason: method, category: 'windowing');
  }
}

class _RbNotesWindows extends StatefulWidget {
  const _RbNotesWindows({
    required this.mainController,
    required this.mainApp,
    required this.settingsManager,
    required this.settingsBuilder,
  });

  final WindowController mainController;
  final Widget mainApp;
  final SettingsWindowManager settingsManager;
  final WidgetBuilder settingsBuilder;

  @override
  State<_RbNotesWindows> createState() => _RbNotesWindowsState();
}

class _RbNotesWindowsState extends State<_RbNotesWindows> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settingsManager,
      builder: (context, _) {
        final settings = widget.settingsManager.window;
        return ViewCollection(
          views: <Widget>[
            Window(controller: widget.mainController, child: widget.mainApp),
            if (settings is _RegularWindowAdapter)
              Window(
                key: ObjectKey(settings),
                controller: settings.controller,
                child: widget.settingsBuilder(context),
              ),
          ],
        );
      },
    );
  }
}

/// [MainWindowHandle] backed by the main [WindowController].
class _MainWindowAdapter implements MainWindowHandle {
  _MainWindowAdapter(this._controller);

  final WindowController _controller;

  @override
  bool get isActive => !_controller.isDestroyed && _controller.isActivated;

  @override
  void activate() {
    if (!_controller.isDestroyed) _controller.activate();
  }
}

class _SettingsWindowDelegate with WindowControllerDelegate {
  _SettingsWindowDelegate(this.onCloseRequested);

  final VoidCallback onCloseRequested;

  @override
  void onWindowCloseRequested(WindowController controller) {
    // Route the native close (red button / ⌘W / menu) through the manager so
    // it clears its single-instance state and stops rendering the window.
    onCloseRequested();
  }
}

/// Real [NativeWindow] backed by a regular [WindowController].
class _RegularWindowAdapter extends ChangeNotifier implements NativeWindow {
  _RegularWindowAdapter({
    required String title,
    required VoidCallback onCloseRequested,
  }) {
    controller = WindowController(
      size: _settingsWindowSize,
      constraints: const BoxConstraints.tightFor(width: 700, height: 580),
      title: title,
      delegate: _SettingsWindowDelegate(onCloseRequested),
    );
    controller.addListener(notifyListeners);
    _styleWindow('styleSettingsWindow', controller);
  }

  late final WindowController controller;

  @override
  bool get isAlive => !controller.isDestroyed;

  @override
  void activate() {
    if (controller.isDestroyed) return;
    controller.activate();
  }

  @override
  void setTitle(String title) {
    if (controller.isDestroyed) return;
    controller.setTitle(title);
  }

  @override
  void destroy() {
    controller.removeListener(notifyListeners);
    if (!controller.isDestroyed) controller.destroy();
  }
}
