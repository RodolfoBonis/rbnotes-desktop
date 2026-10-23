import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:rbnotes/features/auth/data/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tela de topo do app.
enum AppScreen { login, onboarding, app }

/// Controla qual tela de topo aparece (login → onboarding → app), observando a
/// autenticação e a flag de onboarding concluído.
class SessionCubit extends Cubit<AppScreen> {
  SessionCubit({required AuthService auth, required SharedPreferences prefs})
    : _auth = auth,
      _prefs = prefs,
      super(_initial(auth, prefs)) {
    _sub = _auth.authState.listen(_onAuthChanged);
  }

  final AuthService _auth;
  final SharedPreferences _prefs;
  StreamSubscription<AuthUser?>? _sub;

  static const _kOnboarded = 'onboarding.completed';

  static AppScreen _initial(AuthService auth, SharedPreferences prefs) {
    if (auth.currentUser == null) return AppScreen.login;
    return (prefs.getBool(_kOnboarded) ?? false)
        ? AppScreen.app
        : AppScreen.onboarding;
  }

  bool get onboarded => _prefs.getBool(_kOnboarded) ?? false;

  void _onAuthChanged(AuthUser? user) {
    if (user == null) {
      emit(AppScreen.login);
    } else if (!onboarded) {
      emit(AppScreen.onboarding);
    } else {
      emit(AppScreen.app);
    }
  }

  /// Conclui o onboarding e entra no app.
  Future<void> completeOnboarding() async {
    await _prefs.setBool(_kOnboarded, true);
    emit(AppScreen.app);
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
