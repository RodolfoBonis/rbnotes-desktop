import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/native/rb_native.dart';

enum PermState { no, wait, ok }

/// Permissões do onboarding (ids batem com o design).
enum OnbPerm { mic, screen, ax, notif }

class OnboardingState extends Equatable {
  const OnboardingState({
    this.step = 0,
    this.permissions = const {
      OnbPerm.mic: PermState.no,
      OnbPerm.screen: PermState.no,
      OnbPerm.ax: PermState.no,
      OnbPerm.notif: PermState.no,
    },
    this.model = WhisperModel.largeV3TurboQ5,
    this.downloadProgress,
  });

  final int step;
  final Map<OnbPerm, PermState> permissions;
  final WhisperModel model;

  /// Progresso do download do modelo (null = não baixando).
  final double? downloadProgress;

  bool get micGranted => permissions[OnbPerm.mic] == PermState.ok;
  bool get downloading => downloadProgress != null;

  OnboardingState copyWith({
    int? step,
    Map<OnbPerm, PermState>? permissions,
    WhisperModel? model,
    double? downloadProgress,
    bool clearDownload = false,
  }) => OnboardingState(
    step: step ?? this.step,
    permissions: permissions ?? this.permissions,
    model: model ?? this.model,
    downloadProgress: clearDownload
        ? null
        : (downloadProgress ?? this.downloadProgress),
  );

  @override
  List<Object?> get props => [step, permissions, model, downloadProgress];
}

/// Fluxo de onboarding em 4 passos (boas-vindas, permissões, modelo, pronto).
class OnboardingCubit extends Cubit<OnboardingState> {
  OnboardingCubit({
    required RbNative native,
    required SettingsStore settings,
    Future<bool> Function()? requestNotifications,
  }) : _native = native,
       _settings = settings,
       _requestNotifications = requestNotifications,
       super(const OnboardingState());

  final RbNative _native;
  final SettingsStore _settings;
  final Future<bool> Function()? _requestNotifications;
  StreamSubscription<double>? _dlSub;

  void next() {
    final s = state;
    if (s.step == 0) {
      emit(s.copyWith(step: 1));
    } else if (s.step == 1) {
      if (s.micGranted) emit(s.copyWith(step: 2));
    } else if (s.step == 2 && !s.downloading) {
      unawaited(_startDownload());
    }
  }

  void back() {
    if (state.downloading || state.step == 0) return;
    emit(state.copyWith(step: state.step - 1));
  }

  void selectModel(WhisperModel model) {
    if (state.downloading) return;
    emit(state.copyWith(model: model));
  }

  Future<void> requestPermission(OnbPerm perm) async {
    _setPerm(perm, PermState.wait);
    try {
      final granted = switch (perm) {
        OnbPerm.mic => await _native.requestPermission(
          RbPermission.microphone,
        ),
        OnbPerm.screen => await _native.requestPermission(
          RbPermission.screenRecording,
        ),
        OnbPerm.ax => await _native.requestPermission(
          RbPermission.accessibility,
        ),
        OnbPerm.notif => null,
      };
      if (perm == OnbPerm.notif) {
        final ok = await (_requestNotifications?.call() ?? Future.value(true));
        _setPerm(perm, ok ? PermState.ok : PermState.no);
      } else {
        _setPerm(
          perm,
          granted == PermissionStatus.granted ? PermState.ok : PermState.no,
        );
      }
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'onboarding_permission',
        category: 'onboarding',
      );
      _setPerm(perm, PermState.no);
    }
  }

  void _setPerm(OnbPerm perm, PermState value) {
    emit(
      state.copyWith(
        permissions: {...state.permissions, perm: value},
      ),
    );
  }

  Future<void> _startDownload() async {
    emit(state.copyWith(downloadProgress: 0));
    await _dlSub?.cancel();
    _dlSub = _native
        .downloadModel(state.model)
        .listen(
          (p) => emit(state.copyWith(downloadProgress: p)),
          onDone: () async {
            await _settings.setModel(state.model);
            emit(state.copyWith(step: 3, clearDownload: true));
          },
          onError: (Object e, StackTrace st) {
            unawaited(
              AppLogger.error(
                e,
                st,
                reason: 'onboarding_download',
                category: 'onboarding',
              ),
            );
            emit(state.copyWith(clearDownload: true));
          },
        );
  }

  @override
  Future<void> close() async {
    await _dlSub?.cancel();
    return super.close();
  }
}
