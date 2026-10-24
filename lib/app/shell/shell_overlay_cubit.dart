import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

/// Estado dos overlays do shell: ⌘K (perguntar), ⌘, (ajustes),
/// corrigir palavra, nova coleção e toast.
class ShellOverlayState extends Equatable {
  const ShellOverlayState({
    this.askOpen = false,
    this.settingsOpen = false,
    this.newCollectionOpen = false,
    this.weeklyOpen = false,
    this.fixWord,
    this.toast,
  });

  final bool askOpen;
  final bool settingsOpen;
  final bool newCollectionOpen;
  final bool weeklyOpen;

  /// Palavra sendo corrigida (null = modal fechado).
  final String? fixWord;

  /// Mensagem de toast efêmera (null = sem toast).
  final String? toast;

  bool get fixOpen => fixWord != null;

  ShellOverlayState copyWith({
    bool? askOpen,
    bool? settingsOpen,
    bool? newCollectionOpen,
    bool? weeklyOpen,
    String? fixWord,
    bool clearFix = false,
    String? toast,
    bool clearToast = false,
  }) => ShellOverlayState(
    askOpen: askOpen ?? this.askOpen,
    settingsOpen: settingsOpen ?? this.settingsOpen,
    newCollectionOpen: newCollectionOpen ?? this.newCollectionOpen,
    weeklyOpen: weeklyOpen ?? this.weeklyOpen,
    fixWord: clearFix ? null : (fixWord ?? this.fixWord),
    toast: clearToast ? null : (toast ?? this.toast),
  );

  @override
  List<Object?> get props => [
    askOpen,
    settingsOpen,
    newCollectionOpen,
    weeklyOpen,
    fixWord,
    toast,
  ];
}

/// Gerencia a abertura/fechamento dos overlays e o toast.
class ShellOverlayCubit extends Cubit<ShellOverlayState> {
  ShellOverlayCubit() : super(const ShellOverlayState());

  Timer? _toastTimer;

  void openAsk() => emit(state.copyWith(askOpen: true, settingsOpen: false));
  void closeAsk() => emit(state.copyWith(askOpen: false));
  void toggleAsk() => state.askOpen ? closeAsk() : openAsk();

  void openSettings() =>
      emit(state.copyWith(settingsOpen: true, askOpen: false));
  void closeSettings() => emit(state.copyWith(settingsOpen: false));
  void toggleSettings() =>
      state.settingsOpen ? closeSettings() : openSettings();

  void openNewCollection() => emit(state.copyWith(newCollectionOpen: true));
  void closeNewCollection() => emit(state.copyWith(newCollectionOpen: false));

  void openWeekly() => emit(state.copyWith(weeklyOpen: true));
  void closeWeekly() => emit(state.copyWith(weeklyOpen: false));

  void openFix(String word) => emit(state.copyWith(fixWord: word));
  void closeFix() => emit(state.copyWith(clearFix: true));

  /// Fecha o overlay de topo no Esc; retorna true se algo foi fechado.
  bool closeTop() {
    if (state.weeklyOpen) {
      closeWeekly();
      return true;
    }
    if (state.fixOpen) {
      closeFix();
      return true;
    }
    if (state.newCollectionOpen) {
      closeNewCollection();
      return true;
    }
    if (state.settingsOpen) {
      closeSettings();
      return true;
    }
    if (state.askOpen) {
      closeAsk();
      return true;
    }
    return false;
  }

  void showToast(String message) {
    emit(state.copyWith(toast: message));
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      if (!isClosed) emit(state.copyWith(clearToast: true));
    });
  }

  @override
  Future<void> close() {
    _toastTimer?.cancel();
    return super.close();
  }
}
