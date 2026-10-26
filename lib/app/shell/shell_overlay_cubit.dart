import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

/// Estado dos overlays do shell: ⌘K (perguntar), corrigir palavra,
/// nova coleção e toast. (Ajustes agora é uma janela nativa própria.)
class ShellOverlayState extends Equatable {
  const ShellOverlayState({
    this.askOpen = false,
    this.newCollectionOpen = false,
    this.weeklyOpen = false,
    this.fixWord,
    this.toast,
    this.meetingApp,
  });

  final bool askOpen;
  final bool newCollectionOpen;
  final bool weeklyOpen;

  /// Palavra sendo corrigida (null = modal fechado).
  final String? fixWord;

  /// Mensagem de toast efêmera (null = sem toast).
  final String? toast;

  /// App da reunião detectada, para o prompt "Gravar esta reunião?" (null =
  /// sem prompt).
  final String? meetingApp;

  bool get fixOpen => fixWord != null;
  bool get meetingOpen => meetingApp != null;

  ShellOverlayState copyWith({
    bool? askOpen,
    bool? newCollectionOpen,
    bool? weeklyOpen,
    String? fixWord,
    bool clearFix = false,
    String? toast,
    bool clearToast = false,
    String? meetingApp,
    bool clearMeeting = false,
  }) => ShellOverlayState(
    askOpen: askOpen ?? this.askOpen,
    newCollectionOpen: newCollectionOpen ?? this.newCollectionOpen,
    weeklyOpen: weeklyOpen ?? this.weeklyOpen,
    fixWord: clearFix ? null : (fixWord ?? this.fixWord),
    toast: clearToast ? null : (toast ?? this.toast),
    meetingApp: clearMeeting ? null : (meetingApp ?? this.meetingApp),
  );

  @override
  List<Object?> get props => [
    askOpen,
    newCollectionOpen,
    weeklyOpen,
    fixWord,
    toast,
    meetingApp,
  ];
}

/// Gerencia a abertura/fechamento dos overlays e o toast.
class ShellOverlayCubit extends Cubit<ShellOverlayState> {
  ShellOverlayCubit() : super(const ShellOverlayState());

  Timer? _toastTimer;

  void openAsk() => emit(state.copyWith(askOpen: true));
  void closeAsk() => emit(state.copyWith(askOpen: false));
  void toggleAsk() => state.askOpen ? closeAsk() : openAsk();

  void openNewCollection() => emit(state.copyWith(newCollectionOpen: true));
  void closeNewCollection() => emit(state.copyWith(newCollectionOpen: false));

  void openWeekly() => emit(state.copyWith(weeklyOpen: true));
  void closeWeekly() => emit(state.copyWith(weeklyOpen: false));

  void openFix(String word) => emit(state.copyWith(fixWord: word));
  void closeFix() => emit(state.copyWith(clearFix: true));

  void openMeetingPrompt(String app) => emit(state.copyWith(meetingApp: app));
  void closeMeetingPrompt() => emit(state.copyWith(clearMeeting: true));

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
    if (state.askOpen) {
      closeAsk();
      return true;
    }
    if (state.meetingOpen) {
      closeMeetingPrompt();
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
