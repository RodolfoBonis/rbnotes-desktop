import 'dart:async';

import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/native/rb_native.dart';

/// State of the "record a note" global-hotkey registration, surfaced in the
/// Atalhos settings tab. A failed registration (conflict with the dictation
/// shortcut or a system hotkey) is user-correctable, so it is tracked here
/// instead of being reported to error monitoring on every boot.
class RecordNoteHotkeyStatus {
  const RecordNoteHotkeyStatus({required this.registered, this.error});

  /// The shortcut is registered and listening.
  final bool registered;

  /// The registration error message (conflict / permission), or null.
  final String? error;

  static const disabled = RecordNoteHotkeyStatus(registered: false);

  bool get hasError => error != null;
}

/// Registers the global "record a note" hotkey (`id: "record_note"`, toggle
/// style) and, on each press, invokes [onTriggered] — wired by the app shell
/// to toggle the recording cubit.
///
/// The hotkey is registered at boot and re-applied when the shortcut changes in
/// Settings. It never throws out of [start]/[applySettings]: a registration
/// failure is captured in [status] (and broadcast on [statusChanges]) so the
/// settings UI can show it.
class RecordNoteHotkeyService {
  RecordNoteHotkeyService({
    required RbNative native,
    required SettingsStore settings,
  }) : _native = native,
       _settings = settings;

  /// Stable id shared with the native side for this shortcut.
  static const hotkeyId = 'record_note';

  final RbNative _native;
  final SettingsStore _settings;

  StreamSubscription<String>? _sub;
  final _statusController =
      StreamController<RecordNoteHotkeyStatus>.broadcast();
  RecordNoteHotkeyStatus _status = RecordNoteHotkeyStatus.disabled;

  /// Called on each press of the record-note hotkey. Set by the app shell once
  /// the recording cubit is available; a press before then is a no-op.
  Future<void> Function()? onTriggered;

  /// Current registration status (for the settings screen).
  RecordNoteHotkeyStatus get status => _status;

  /// Status changes, so an open settings screen reflects a re-registration.
  Stream<RecordNoteHotkeyStatus> get statusChanges => _statusController.stream;

  /// Starts listening for presses and registers the shortcut (if enabled).
  Future<void> start() async {
    _sub = _native.globalHotkeyPressed().listen(
      _onPressed,
      onError: (Object e, StackTrace st) {
        unawaited(
          AppLogger.error(
            e,
            st,
            reason: 'record_hotkey_stream',
            category: 'recording',
          ),
        );
      },
    );
    await applySettings();
  }

  /// Re-registers the shortcut after a change in Settings (enable/disable or a
  /// new combination).
  Future<void> applySettings() async {
    try {
      if (_settings.recordHotkeyEnabled) {
        await _native.registerGlobalHotkey(
          id: hotkeyId,
          hotkey: _settings.recordHotkey,
        );
        _setStatus(const RecordNoteHotkeyStatus(registered: true));
      } else {
        await _native.unregisterGlobalHotkey(hotkeyId);
        _setStatus(RecordNoteHotkeyStatus.disabled);
      }
    } on Object catch (e) {
      // Not a server error: a conflict with the dictation shortcut or a system
      // hotkey. Keep it for the settings screen; breadcrumb only.
      _setStatus(
        RecordNoteHotkeyStatus(
          registered: false,
          error: e is RbNativeException ? e.message : e.toString(),
        ),
      );
      AppLogger.warning(
        'record-note hotkey registration failed',
        category: 'recording',
        error: e,
      );
    }
  }

  void _onPressed(String id) {
    if (id != hotkeyId) return;
    final handler = onTriggered;
    if (handler == null) return;
    unawaited(
      handler().catchError((Object e, StackTrace st) async {
        await AppLogger.error(
          e,
          st,
          reason: 'record_hotkey_trigger',
          category: 'recording',
        );
      }),
    );
  }

  void _setStatus(RecordNoteHotkeyStatus status) {
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    onTriggered = null;
    try {
      await _native.unregisterGlobalHotkey(hotkeyId);
    } on Object catch (_) {
      // shutting down; ignore.
    }
    await _statusController.close();
  }
}
