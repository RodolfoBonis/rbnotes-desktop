import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/native/rb_native.dart';

enum ModelStatus { unknown, checking, downloaded, missing, downloading, failed }

class ModelDownloadState extends Equatable {
  const ModelDownloadState({
    this.status = ModelStatus.unknown,
    this.progress = 0,
    this.sizeBytes,
  });

  final ModelStatus status;
  final double progress;
  final int? sizeBytes;

  ModelDownloadState copyWith({
    ModelStatus? status,
    double? progress,
    int? sizeBytes,
  }) => ModelDownloadState(
    status: status ?? this.status,
    progress: progress ?? this.progress,
    sizeBytes: sizeBytes ?? this.sizeBytes,
  );

  @override
  List<Object?> get props => [status, progress, sizeBytes];
}

/// Onboarding do modelo whisper: verifica se está baixado e baixa
/// com progresso.
class ModelDownloadCubit extends Cubit<ModelDownloadState> {
  ModelDownloadCubit({
    required RbNative native,
    required SettingsStore settings,
  }) : _native = native,
       _settings = settings,
       super(const ModelDownloadState());

  final RbNative _native;
  final SettingsStore _settings;
  StreamSubscription<double>? _sub;

  WhisperModel get model => _settings.model;

  Future<void> check() async {
    emit(state.copyWith(status: ModelStatus.checking));
    try {
      final result = await _native.modelState(model);
      emit(
        state.copyWith(
          status: result.downloaded
              ? ModelStatus.downloaded
              : ModelStatus.missing,
          sizeBytes: result.sizeBytes,
        ),
      );
    } on RbNativeException catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'model_state',
        category: 'transcription',
      );
      emit(state.copyWith(status: ModelStatus.failed));
    }
  }

  Future<void> download() async {
    if (state.status == ModelStatus.downloading) return;
    emit(state.copyWith(status: ModelStatus.downloading, progress: 0));
    final completer = Completer<void>();
    await _sub?.cancel();
    _sub = _native
        .downloadModel(model)
        .listen(
          (p) => emit(state.copyWith(progress: p.clamp(0, 1))),
          onError: (Object e, StackTrace st) {
            unawaited(
              AppLogger.error(
                e,
                st,
                reason: 'model_download',
                category: 'transcription',
              ),
            );
            emit(state.copyWith(status: ModelStatus.failed));
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            if (state.status == ModelStatus.downloading) {
              emit(state.copyWith(status: ModelStatus.downloaded, progress: 1));
            }
            if (!completer.isCompleted) completer.complete();
          },
        );
    return completer.future;
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
