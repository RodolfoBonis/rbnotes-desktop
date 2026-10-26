import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/auth/oidc_client.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/auth/data/auth_service.dart';

enum AuthMode { login, signup }

class LoginState extends Equatable {
  const LoginState({
    this.mode = AuthMode.login,
    this.name = '',
    this.email = '',
    this.password = '',
    this.loading = false,
    this.error,
  });

  final AuthMode mode;
  final String name;
  final String email;
  final String password;
  final bool loading;
  final String? error;

  bool get isSignup => mode == AuthMode.signup;

  LoginState copyWith({
    AuthMode? mode,
    String? name,
    String? email,
    String? password,
    bool? loading,
    String? error,
    bool clearError = false,
  }) => LoginState(
    mode: mode ?? this.mode,
    name: name ?? this.name,
    email: email ?? this.email,
    password: password ?? this.password,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [mode, name, email, password, loading, error];
}

/// Estado do formulário de login/cadastro. A navegação após autenticar é
/// reativa (o `SessionCubit` observa o `AuthService`).
class LoginCubit extends Cubit<LoginState> {
  LoginCubit(this._auth) : super(const LoginState());

  final AuthService _auth;

  void setName(String v) => emit(state.copyWith(name: v, clearError: true));
  void setEmail(String v) => emit(state.copyWith(email: v, clearError: true));
  void setPassword(String v) =>
      emit(state.copyWith(password: v, clearError: true));

  void toggleMode() => emit(
    state.copyWith(
      mode: state.isSignup ? AuthMode.login : AuthMode.signup,
      clearError: true,
    ),
  );

  Future<void> submit() async {
    if (state.loading) return;
    emit(state.copyWith(loading: true, clearError: true));
    try {
      if (state.isSignup) {
        await _auth.signUp(state.name, state.email, state.password);
      } else {
        await _auth.signInWithEmail(state.email, state.password);
      }
    } on Object catch (e, st) {
      emit(state.copyWith(loading: false, error: await _messageFor(e, st)));
    }
  }

  Future<void> signInWithGoogle() async {
    if (state.loading) return;
    emit(state.copyWith(loading: true, clearError: true));
    try {
      await _auth.signInWithGoogle();
    } on Object catch (e, st) {
      emit(state.copyWith(loading: false, error: await _messageFor(e, st)));
    }
  }

  /// Mensagem acionável para a falha de login (e registro no log).
  static Future<String> _messageFor(Object error, StackTrace stack) async {
    if (error is AuthException) return error.message;
    if (error is OidcException && error.isNetwork) {
      AppLogger.warning('Login sem conexão', category: 'auth', error: error);
      return 'Sem conexão com o servidor de login. Verifique a internet, a '
          'VPN ou o DNS e tente de novo.';
    }
    await AppLogger.error(error, stack, reason: 'login', category: 'auth');
    return 'Não foi possível entrar.';
  }
}
