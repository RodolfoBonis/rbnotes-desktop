import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rbnotes/features/dictation/data/dictation_service.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/native/rb_native.dart';

class SettingsState extends Equatable {
  const SettingsState({
    required this.model,
    required this.captureSystemAudio,
    required this.dictationEnabled,
    required this.dictationMode,
    required this.hotkey,
    this.permissions = const {},
  });

  final WhisperModel model;
  final bool captureSystemAudio;
  final bool dictationEnabled;
  final DictationMode dictationMode;
  final Hotkey hotkey;
  final Map<RbPermission, PermissionStatus> permissions;

  PermissionStatus statusOf(RbPermission p) =>
      permissions[p] ?? PermissionStatus.notDetermined;

  SettingsState copyWith({
    WhisperModel? model,
    bool? captureSystemAudio,
    bool? dictationEnabled,
    DictationMode? dictationMode,
    Hotkey? hotkey,
    Map<RbPermission, PermissionStatus>? permissions,
  }) => SettingsState(
    model: model ?? this.model,
    captureSystemAudio: captureSystemAudio ?? this.captureSystemAudio,
    dictationEnabled: dictationEnabled ?? this.dictationEnabled,
    dictationMode: dictationMode ?? this.dictationMode,
    hotkey: hotkey ?? this.hotkey,
    permissions: permissions ?? this.permissions,
  );

  @override
  List<Object?> get props => [
    model,
    captureSystemAudio,
    dictationEnabled,
    dictationMode,
    hotkey,
    permissions,
  ];
}

/// Configurações do app: modelo, atalho do ditado, áudio do sistema e o
/// status das permissões do sistema.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required SettingsStore store,
    required RbNative native,
    required DictationService dictation,
  }) : _store = store,
       _native = native,
       _dictation = dictation,
       super(
         SettingsState(
           model: store.model,
           captureSystemAudio: store.captureSystemAudio,
           dictationEnabled: store.dictationEnabled,
           dictationMode: store.dictationMode,
           hotkey: store.hotkey,
         ),
       );

  final SettingsStore _store;
  final RbNative _native;
  final DictationService _dictation;

  Future<void> refreshPermissions() async {
    final entries = <RbPermission, PermissionStatus>{};
    for (final p in RbPermission.values) {
      entries[p] = await _native.permissionStatus(p);
    }
    emit(state.copyWith(permissions: entries));
  }

  Future<void> requestPermission(RbPermission p) async {
    final status = await _native.requestPermission(p);
    final next = Map<RbPermission, PermissionStatus>.from(state.permissions)
      ..[p] = status;
    emit(state.copyWith(permissions: next));
  }

  Future<void> setModel(WhisperModel model) async {
    await _store.setModel(model);
    emit(state.copyWith(model: model));
  }

  Future<void> setCaptureSystemAudio({required bool value}) async {
    await _store.setCaptureSystemAudio(value: value);
    emit(state.copyWith(captureSystemAudio: value));
  }

  Future<void> setDictationEnabled({required bool value}) async {
    await _store.setDictationEnabled(value: value);
    emit(state.copyWith(dictationEnabled: value));
    await _dictation.applySettings();
  }

  Future<void> setDictationMode(DictationMode mode) async {
    await _store.setDictationMode(mode);
    emit(state.copyWith(dictationMode: mode));
    await _dictation.applySettings();
  }

  Future<void> setHotkey(Hotkey hotkey) async {
    await _store.setHotkey(hotkey);
    emit(state.copyWith(hotkey: hotkey));
    await _dictation.applySettings();
  }
}
