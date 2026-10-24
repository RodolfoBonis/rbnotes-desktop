import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rbnotes/features/security/data/biometric_auth.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/native/rb_native.dart';

class AppLockState extends Equatable {
  const AppLockState({
    required this.enabled,
    required this.locked,
    this.authenticating = false,
  });

  /// "Bloquear com Touch ID" ligado (aba Privacidade).
  final bool enabled;

  /// A tela de bloqueio está cobrindo o app.
  final bool locked;

  /// Uma tentativa de desbloqueio está em andamento (Touch ID na tela).
  final bool authenticating;

  AppLockState copyWith({bool? enabled, bool? locked, bool? authenticating}) =>
      AppLockState(
        enabled: enabled ?? this.enabled,
        locked: locked ?? this.locked,
        authenticating: authenticating ?? this.authenticating,
      );

  @override
  List<Object?> get props => [enabled, locked, authenticating];
}

/// Trava do app inteiro por Touch ID.
///
/// Quando "Bloquear com Touch ID" está ligado, os gatilhos nativos
/// ([RbNative.lockTriggers]: tela bloqueada, sono, proteção de tela) cobrem a
/// janela com a tela de bloqueio. O diário passa a ser coberto por esta mesma
/// trava (a trava separada do diário foi removida). Enquanto
/// [AppLockState.locked] é true, o overlay do notch e a tray não mostram
/// conteúdo e os atalhos globais não abrem notas.
class AppLockCubit extends Cubit<AppLockState> {
  AppLockCubit({
    required RbNative native,
    required BiometricAuth auth,
    required SettingsStore settings,
  }) : _auth = auth,
       _settings = settings,
       super(
         AppLockState(
           enabled: settings.touchIdLock,
           // Ao abrir o app já travado, exige o desbloqueio.
           locked: settings.touchIdLock,
         ),
       ) {
    _sub = native.lockTriggers().listen((_) => lock());
  }

  final BiometricAuth _auth;
  final SettingsStore _settings;
  StreamSubscription<LockTrigger>? _sub;

  /// Liga/desliga a trava (aba Privacidade). Ao desligar, destrava.
  Future<void> setEnabled({required bool enabled}) async {
    await _settings.setTouchIdLock(value: enabled);
    emit(state.copyWith(enabled: enabled, locked: enabled && state.locked));
  }

  /// Cobre o app com a tela de bloqueio (gatilho nativo ou manual).
  void lock() {
    if (!state.enabled || state.locked) return;
    emit(state.copyWith(locked: true));
  }

  /// Tenta desbloquear com Touch ID (fallback para a senha do Mac).
  Future<bool> unlock() async {
    if (!state.locked || state.authenticating) return !state.locked;
    emit(state.copyWith(authenticating: true));
    final ok = await _auth.authenticate('Desbloquear o RbNotes');
    emit(state.copyWith(locked: !ok, authenticating: false));
    return ok;
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
