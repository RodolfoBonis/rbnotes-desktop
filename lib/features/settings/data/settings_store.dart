import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferências do RbNotes, persistidas em SharedPreferences.
///
/// Atalho padrão: ⌥Space (keyCode 49 no macOS), modo segurar-para-falar.
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kModel = 'settings.model';
  static const _kCaptureSystem = 'settings.capture_system_audio';
  static const _kHotkeyKeyCode = 'settings.hotkey.key_code';
  static const _kHotkeyModifiers = 'settings.hotkey.modifiers';
  static const _kDictationMode = 'settings.dictation.mode';
  static const _kDictationEnabled = 'settings.dictation.enabled';

  /// Space no macOS.
  static const defaultHotkey = Hotkey(
    keyCode: 49,
    modifiers: {HotkeyModifier.option},
  );

  WhisperModel get model => WhisperModel.values.firstWhere(
    (m) => m.name == _prefs.getString(_kModel),
    orElse: () => WhisperModel.largeV3TurboQ5,
  );

  Future<void> setModel(WhisperModel model) =>
      _prefs.setString(_kModel, model.name);

  bool get captureSystemAudio => _prefs.getBool(_kCaptureSystem) ?? false;

  Future<void> setCaptureSystemAudio({required bool value}) =>
      _prefs.setBool(_kCaptureSystem, value);

  bool get dictationEnabled => _prefs.getBool(_kDictationEnabled) ?? true;

  Future<void> setDictationEnabled({required bool value}) =>
      _prefs.setBool(_kDictationEnabled, value);

  DictationMode get dictationMode => DictationMode.values.firstWhere(
    (m) => m.name == _prefs.getString(_kDictationMode),
    orElse: () => DictationMode.holdToTalk,
  );

  Future<void> setDictationMode(DictationMode mode) =>
      _prefs.setString(_kDictationMode, mode.name);

  Hotkey get hotkey {
    final keyCode = _prefs.getInt(_kHotkeyKeyCode);
    if (keyCode == null) return defaultHotkey;
    final mods = (_prefs.getStringList(_kHotkeyModifiers) ?? const [])
        .map(
          (n) => HotkeyModifier.values.firstWhere(
            (m) => m.name == n,
            orElse: () => HotkeyModifier.option,
          ),
        )
        .toSet();
    return Hotkey(keyCode: keyCode, modifiers: mods);
  }

  Future<void> setHotkey(Hotkey hotkey) async {
    await _prefs.setInt(_kHotkeyKeyCode, hotkey.keyCode);
    await _prefs.setStringList(
      _kHotkeyModifiers,
      hotkey.modifiers.map((m) => m.name).toList(),
    );
  }
}
