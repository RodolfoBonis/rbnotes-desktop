import 'package:flutter/material.dart';
import 'package:rbnotes/core/theme/accent_presets.dart';
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
  static const _kNoteReadyNotif = 'settings.notif.note_ready';
  static const _kDiaryPromptNotif = 'settings.notif.diary_prompt';
  static const _kTaskReminderHour = 'settings.notif.task_hour';
  static const _kTaskEveReminder = 'settings.notif.task_eve';
  static const _kDiaryPromptHour = 'settings.notif.diary_hour';
  static const _kWeeklySummaryHour = 'settings.notif.weekly_hour';
  static const _kLastWeeklyAt = 'settings.notif.last_weekly_at';
  static const _kScheduledTaskKeys = 'settings.notif.task_keys';
  // Cache da pergunta do diário: 1 chamada de IA por data (ver coordinator).
  static const _kDiaryPromptDate = 'settings.notif.diary_prompt.date';
  static const _kDiaryPromptText = 'settings.notif.diary_prompt.text';
  static const _kDiaryPromptRetryAt = 'settings.notif.diary_prompt.retry_at';
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
  static const _kSendAudio = 'settings.send_audio';
  static const _kTouchId = 'settings.touch_id';
  static const _kKeyCheck = 'settings.note_lock.key_check';
  static const _kRetention = 'settings.retention';
  static const _kDeleteAudio = 'settings.delete_audio';
  // Aparência
  static const _kAccentArgb = 'settings.accent.argb';

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

  /// Notificação "Nota pronta" ao fim do pipeline (janela fora de foco).
  bool get noteReadyNotif => _prefs.getBool(_kNoteReadyNotif) ?? true;
  Future<void> setNoteReadyNotif({required bool value}) =>
      _prefs.setBool(_kNoteReadyNotif, value);

  /// Notificação da pergunta do diário.
  bool get diaryPromptNotif => _prefs.getBool(_kDiaryPromptNotif) ?? true;
  Future<void> setDiaryPromptNotif({required bool value}) =>
      _prefs.setBool(_kDiaryPromptNotif, value);

  /// Hora (0..23) do lembrete de tarefas com prazo (padrão 9h).
  int get taskReminderHour => _prefs.getInt(_kTaskReminderHour) ?? 9;
  Future<void> setTaskReminderHour(int hour) =>
      _prefs.setInt(_kTaskReminderHour, hour);

  /// Lembrar também na véspera do prazo.
  bool get taskEveReminder => _prefs.getBool(_kTaskEveReminder) ?? false;
  Future<void> setTaskEveReminder({required bool value}) =>
      _prefs.setBool(_kTaskEveReminder, value);

  /// Hora (0..23) da pergunta do diário (padrão 21h).
  int get diaryPromptHour => _prefs.getInt(_kDiaryPromptHour) ?? 21;
  Future<void> setDiaryPromptHour(int hour) =>
      _prefs.setInt(_kDiaryPromptHour, hour);

  /// Hora (0..23) do resumo semanal, toda segunda (padrão 9h).
  int get weeklySummaryHour => _prefs.getInt(_kWeeklySummaryHour) ?? 9;
  Future<void> setWeeklySummaryHour(int hour) =>
      _prefs.setInt(_kWeeklySummaryHour, hour);

  /// Quando o último resumo semanal foi gerado (para gerar na 1ª abertura se o
  /// horário passou com o app fechado).
  DateTime? get lastWeeklySummaryAt {
    final raw = _prefs.getString(_kLastWeeklyAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastWeeklySummaryAt(DateTime at) =>
      _prefs.setString(_kLastWeeklyAt, at.toUtc().toIso8601String());

  /// Keys das tarefas com lembrete agendado (para cancelar as removidas no
  /// reagendamento).
  List<String> get scheduledTaskKeys =>
      _prefs.getStringList(_kScheduledTaskKeys) ?? const [];
  Future<void> setScheduledTaskKeys(List<String> keys) =>
      _prefs.setStringList(_kScheduledTaskKeys, keys);

  /// Pergunta do diário já gerada pela IA para a data [ymd] (`yyyy-MM-dd`), ou
  /// null se não há cache para essa data. Guarda uma única entrada: como só há
  /// uma pergunta futura agendada por vez, a data anterior é descartada ao
  /// gravar a nova (poda implícita).
  String? cachedDiaryPrompt(String ymd) =>
      _prefs.getString(_kDiaryPromptDate) == ymd
      ? _prefs.getString(_kDiaryPromptText)
      : null;

  /// Persiste a pergunta do diário de [ymd], substituindo qualquer data antiga.
  Future<void> setCachedDiaryPrompt(String ymd, String prompt) async {
    await _prefs.setString(_kDiaryPromptDate, ymd);
    await _prefs.setString(_kDiaryPromptText, prompt);
  }

  /// Instante até o qual não se deve tentar gerar a pergunta do diário de novo
  /// (backoff após limite diário/rede), ou null se não há backoff ativo.
  DateTime? get diaryPromptRetryAt {
    final raw = _prefs.getString(_kDiaryPromptRetryAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setDiaryPromptRetryAt(DateTime at) =>
      _prefs.setString(_kDiaryPromptRetryAt, at.toUtc().toIso8601String());

  Future<void> clearDiaryPromptRetryAt() => _prefs.remove(_kDiaryPromptRetryAt);

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

  /// Código de idioma para o whisper (`auto`/`pt`/`en`/`es`).
  String get languageCode => switch (language) {
    'Português (Brasil)' => 'pt',
    'English' => 'en',
    'Español' => 'es',
    _ => 'auto',
  };

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

  /// "Enviar áudios": separado do sync, controla o `AudioUploadQueue`. Padrão
  /// desligado — o áudio só sobe quando o dono liga explicitamente.
  bool get sendAudio => _prefs.getBool(_kSendAudio) ?? false;
  Future<void> setSendAudio({required bool value}) =>
      _prefs.setBool(_kSendAudio, value);

  bool get touchIdLock => _prefs.getBool(_kTouchId) ?? false;
  Future<void> setTouchIdLock({required bool value}) =>
      _prefs.setBool(_kTouchId, value);

  /// Sentinela da chave das notas bloqueadas (M10): um envelope cifrado com a
  /// chave atual, guardado em claro (é só ciphertext) para validar uma chave de
  /// recuperação importada — se não decifrar o sentinela, não abre as notas.
  String? get noteKeyCheck => _prefs.getString(_kKeyCheck);
  Future<void> setNoteKeyCheck(String value) =>
      _prefs.setString(_kKeyCheck, value);

  String get retention => _prefs.getString(_kRetention) ?? '1 ano';
  Future<void> setRetention(String value) =>
      _prefs.setString(_kRetention, value);

  bool get deleteAudioAfter => _prefs.getBool(_kDeleteAudio) ?? false;
  Future<void> setDeleteAudioAfter({required bool value}) =>
      _prefs.setBool(_kDeleteAudio, value);

  // ---- Aparência: cor de acento ----

  /// Cor de acento escolhida (preset ou personalizada). Default: o laranja do
  /// design (#E0512E).
  Color get accentColor {
    final argb = _prefs.getInt(_kAccentArgb);
    return argb != null ? Color(argb) : AccentPresets.fallback.color;
  }

  Future<void> setAccentColor(Color color) =>
      _prefs.setInt(_kAccentArgb, color.toARGB32());
}
