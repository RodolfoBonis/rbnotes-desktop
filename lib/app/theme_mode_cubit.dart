import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferência de tema (claro/escuro/sistema), persistida localmente.
class ThemeModeCubit extends Cubit<ThemeMode> {
  ThemeModeCubit(this._prefs) : super(_parse(_prefs.getString(_key)));

  final SharedPreferences _prefs;
  static const _key = 'ui.theme_mode';

  static ThemeMode _parse(String? v) => ThemeMode.values.firstWhere(
    (m) => m.name == v,
    orElse: () => ThemeMode.system,
  );

  Future<void> set(ThemeMode mode) async {
    emit(mode);
    await _prefs.setString(_key, mode.name);
  }

  Future<void> toggle(Brightness current) =>
      set(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}
