import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:rbnotes/core/theme/accent_presets.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';

/// Holds the current accent [Color] and persists it. The whole app theme is
/// rebuilt when it changes (see `RbNotesApp`), giving a live preview.
class AccentCubit extends Cubit<Color> {
  AccentCubit(this._settings) : super(_settings.accentColor);

  final SettingsStore _settings;

  /// Selects a named preset.
  Future<void> selectPreset(AccentPreset preset) => setColor(preset.color);

  /// Sets an arbitrary custom color.
  Future<void> setColor(Color color) async {
    if (color.toARGB32() == state.toARGB32()) return;
    emit(color);
    await _settings.setAccentColor(color);
  }

  /// The preset matching the current color, or null when it is custom.
  AccentPreset? get selectedPreset => AccentPresets.forColor(state);
}
