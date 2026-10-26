import 'package:flutter/foundation.dart';
import 'package:rbnotes/core/windowing/main_window.dart';
import 'package:rbnotes/core/windowing/settings_window_manager.dart';

/// A [NativeWindow] that records calls instead of touching the platform, for
/// tests of the Settings-window open/focus/single-instance logic (and to stand
/// in for the real window wherever `AppShell` resolves a manager from DI).
class FakeNativeWindow extends ChangeNotifier implements NativeWindow {
  FakeNativeWindow({required this.title});

  String title;
  int activateCount = 0;
  bool destroyed = false;

  @override
  bool get isAlive => !destroyed;

  @override
  void activate() => activateCount++;

  @override
  void setTitle(String title) => this.title = title;

  @override
  void destroy() => destroyed = true;
}

/// Builds a [SettingsWindowManager] backed by [FakeNativeWindow]s. [onCreate]
/// receives each window as it is created, so tests can assert on it.
SettingsWindowManager fakeSettingsWindowManager({
  void Function(FakeNativeWindow window)? onCreate,
  String initialTitle = 'Geral',
}) {
  return SettingsWindowManager(
    createWindow: ({required title, required onCloseRequested}) {
      final window = FakeNativeWindow(title: title);
      onCreate?.call(window);
      return window;
    },
    resolveInitialTitle: () => initialTitle,
  );
}

/// A [MainWindowHandle] for tests: reports a configurable focus state and
/// records activate() calls.
class FakeMainWindowHandle implements MainWindowHandle {
  FakeMainWindowHandle({this.active = true});

  bool active;
  int activateCount = 0;

  @override
  bool get isActive => active;

  @override
  void activate() => activateCount++;
}
