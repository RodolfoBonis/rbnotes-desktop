import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferências do RbNotes, persistidas em SharedPreferences.
///
/// Cobre todas as opções das 7 abas de Configurações do design v3. O tema
/// (claro/escuro/sistema) fica no `ThemeModeCubit`; o resto está aqui.
///
/// Atalho padrão: ⌥Space (keyCode 49 no macOS), modo segurar-para-falar.
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  // ---- chaves ----
  static const _kModel = 'settings.model';
  static const _kCaptureSystem = 'settings.capture_system_audio';
  static const _kHotkeyKeyCode = 'settings.hotkey.key_code';
  static const _kHotkeyModifiers = 'settings.hotkey.modifiers';
  static const _kDictationMode = 'settings.dictation.mode';
  static const _kDictationEnabled = 'settings.dictation.enabled';
  static const _kRecordHotkeyKeyCode = 'settings.record_hotkey.key_code';
  static const _kRecordHotkeyModifiers = 'settings.record_hotkey.modifiers';
  static const _kRecordHotkeyEnabled = 'settings.record_hotkey.enabled';
  // Geral
  static const _kLaunchAtLogin = 'settings.launch_at_login';
  static const _kShowInMenuBar = 'settings.menu_bar';
  static const _kDefaultFolder = 'settings.default_folder';
  static const _kWeeklySummary = 'settings.weekly_summary';
  static const _kRemindTasks = 'settings.remind_tasks';
  // Gravação
  static const _kMicDeviceId = 'settings.mic_device_id';
  static const _kMicName = 'settings.mic_name';
  static const _kAutoMeet = 'settings.auto_meet';
  static const _kNoiseReduction = 'settings.noise_reduction';
  static const _kRemoveSilences = 'settings.remove_silences';
  // Transcrição
  static const _kLanguage = 'settings.language';
  static const _kIdentifySpeakers = 'settings.identify_speakers';
  // Inteligência
  static const _kAutoSummary = 'settings.auto_summary';
  static const _kExtractTasks = 'settings.extract_tasks';
  static const _kSummaryStyle = 'settings.summary_style';
  static const _kSummaryLength = 'settings.summary_length';
  static const _kAiModel = 'settings.ai_model';
  static const _kSkipPersonal = 'settings.skip_personal';
  static const _kRedact = 'settings.redact';
  // Conta / Privacidade
  static const _kSync = 'settings.sync';
  static const _kTouchId = 'settings.touch_id';
  static const _kRetention = 'settings.retention';
  static const _kDeleteAudio = 'settings.delete_audio';

  /// Space no macOS.
  static const defaultHotkey = Hotkey(
    keyCode: 49,
    modifiers: {HotkeyModifier.option},
  );

  // ---- Transcrição / ditado ----

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

  // ---- Atalho global "Gravar nota" (toggle) ----

  /// ⌥⇧Espaço no macOS (keyCode 49). Difere do ditado (⌥Espaço) para os dois
  /// atalhos globais coexistirem sem conflito.
  static const defaultRecordHotkey = Hotkey(
    keyCode: 49,
    modifiers: {HotkeyModifier.option, HotkeyModifier.shift},
  );

  bool get recordHotkeyEnabled => _prefs.getBool(_kRecordHotkeyEnabled) ?? true;

  Future<void> setRecordHotkeyEnabled({required bool value}) =>
      _prefs.setBool(_kRecordHotkeyEnabled, value);

  Hotkey get recordHotkey {
    final keyCode = _prefs.getInt(_kRecordHotkeyKeyCode);
    if (keyCode == null) return defaultRecordHotkey;
    final mods = (_prefs.getStringList(_kRecordHotkeyModifiers) ?? const [])
        .map(
          (n) => HotkeyModifier.values.firstWhere(
            (m) => m.name == n,
            orElse: () => HotkeyModifier.option,
          ),
        )
        .toSet();
    return Hotkey(keyCode: keyCode, modifiers: mods);
  }

  Future<void> setRecordHotkey(Hotkey hotkey) async {
    await _prefs.setInt(_kRecordHotkeyKeyCode, hotkey.keyCode);
    await _prefs.setStringList(
      _kRecordHotkeyModifiers,
      hotkey.modifiers.map((m) => m.name).toList(),
    );
  }

  // ---- Geral ----

  bool get launchAtLogin => _prefs.getBool(_kLaunchAtLogin) ?? true;
  Future<void> setLaunchAtLogin({required bool value}) =>
      _prefs.setBool(_kLaunchAtLogin, value);

  bool get showInMenuBar => _prefs.getBool(_kShowInMenuBar) ?? true;
  Future<void> setShowInMenuBar({required bool value}) =>
      _prefs.setBool(_kShowInMenuBar, value);

  String get defaultFolder => _prefs.getString(_kDefaultFolder) ?? 'ideias';
  Future<void> setDefaultFolder(String folderId) =>
      _prefs.setString(_kDefaultFolder, folderId);

  bool get weeklySummary => _prefs.getBool(_kWeeklySummary) ?? true;
  Future<void> setWeeklySummary({required bool value}) =>
      _prefs.setBool(_kWeeklySummary, value);

  bool get remindTasks => _prefs.getBool(_kRemindTasks) ?? true;
  Future<void> setRemindTasks({required bool value}) =>
      _prefs.setBool(_kRemindTasks, value);

  // ---- Gravação ----

  String? get micDeviceId => _prefs.getString(_kMicDeviceId);
  String get micName =>
      _prefs.getString(_kMicName) ?? 'Microfone do MacBook Pro';
  Future<void> setMic(String? deviceId, String name) async {
    if (deviceId == null) {
      await _prefs.remove(_kMicDeviceId);
    } else {
      await _prefs.setString(_kMicDeviceId, deviceId);
    }
    await _prefs.setString(_kMicName, name);
  }

  bool get autoMeet => _prefs.getBool(_kAutoMeet) ?? false;
  Future<void> setAutoMeet({required bool value}) =>
      _prefs.setBool(_kAutoMeet, value);

  bool get noiseReduction => _prefs.getBool(_kNoiseReduction) ?? true;
  Future<void> setNoiseReduction({required bool value}) =>
      _prefs.setBool(_kNoiseReduction, value);

  bool get removeSilences => _prefs.getBool(_kRemoveSilences) ?? true;
  Future<void> setRemoveSilences({required bool value}) =>
      _prefs.setBool(_kRemoveSilences, value);

  // ---- Transcrição ----

  String get language =>
      _prefs.getString(_kLanguage) ?? 'Detectar automaticamente';
  Future<void> setLanguage(String value) => _prefs.setString(_kLanguage, value);

  bool get identifySpeakers => _prefs.getBool(_kIdentifySpeakers) ?? true;
  Future<void> setIdentifySpeakers({required bool value}) =>
      _prefs.setBool(_kIdentifySpeakers, value);

  // ---- Inteligência ----

  bool get autoSummary => _prefs.getBool(_kAutoSummary) ?? true;
  Future<void> setAutoSummary({required bool value}) =>
      _prefs.setBool(_kAutoSummary, value);

  bool get extractTasks => _prefs.getBool(_kExtractTasks) ?? true;
  Future<void> setExtractTasks({required bool value}) =>
      _prefs.setBool(_kExtractTasks, value);

  SummaryStyle get summaryStyle => SummaryStyle.values.firstWhere(
    (s) => s.name == _prefs.getString(_kSummaryStyle),
    orElse: () => SummaryStyle.objetivo,
  );
  Future<void> setSummaryStyle(SummaryStyle value) =>
      _prefs.setString(_kSummaryStyle, value.name);

  SummaryLength get summaryLength => SummaryLength.values.firstWhere(
    (s) => s.name == _prefs.getString(_kSummaryLength),
    orElse: () => SummaryLength.medio,
  );
  Future<void> setSummaryLength(SummaryLength value) =>
      _prefs.setString(_kSummaryLength, value.name);

  String get aiModel => _prefs.getString(_kAiModel) ?? 'Claude Sonnet';
  Future<void> setAiModel(String value) => _prefs.setString(_kAiModel, value);

  bool get skipPersonal => _prefs.getBool(_kSkipPersonal) ?? true;
  Future<void> setSkipPersonal({required bool value}) =>
      _prefs.setBool(_kSkipPersonal, value);

  bool get redactSensitive => _prefs.getBool(_kRedact) ?? true;
  Future<void> setRedactSensitive({required bool value}) =>
      _prefs.setBool(_kRedact, value);

  // ---- Conta / Privacidade ----

  bool get syncEnabled => _prefs.getBool(_kSync) ?? true;
  Future<void> setSyncEnabled({required bool value}) =>
      _prefs.setBool(_kSync, value);

  bool get touchIdLock => _prefs.getBool(_kTouchId) ?? false;
  Future<void> setTouchIdLock({required bool value}) =>
      _prefs.setBool(_kTouchId, value);

  String get retention => _prefs.getString(_kRetention) ?? '1 ano';
  Future<void> setRetention(String value) =>
      _prefs.setString(_kRetention, value);

  bool get deleteAudioAfter => _prefs.getBool(_kDeleteAudio) ?? false;
  Future<void> setDeleteAudioAfter({required bool value}) =>
      _prefs.setBool(_kDeleteAudio, value);
}
