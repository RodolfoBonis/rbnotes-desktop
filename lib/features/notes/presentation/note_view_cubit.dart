import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/audio_player_controller.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:uuid/uuid.dart';

/// Abas do detalhe da nota.
enum NoteTab { resumo, trans, ins, chat }

class NoteViewState extends Equatable {
  const NoteViewState({
    this.note,
    this.ai,
    this.segments = const [],
    this.actions = const [],
    this.chat = const [],
    this.tab = NoteTab.resumo,
    this.playing = false,
    this.positionMs = 0,
    this.speed = 1,
    this.peaks = const [],
    this.chatInput = '',
    this.chatThinking = false,
    this.streamingText,
    this.streamingCites = const [],
  });

  final NoteRow? note;
  final NoteAi? ai;
  final List<SegmentRow> segments;
  final List<ActionRow> actions;
  final List<ChatMessageRow> chat;
  final NoteTab tab;
  final bool playing;
  final int positionMs;
  final double speed;
  final List<double> peaks;
  final String chatInput;
  final bool chatThinking;

  /// Texto do streaming da resposta de IA em andamento (null quando ocioso).
  final String? streamingText;
  final List<int> streamingCites;

  int get durationMs => note?.durationMs ?? 0;

  NoteViewState copyWith({
    NoteRow? note,
    NoteAi? ai,
    bool clearAi = false,
    List<SegmentRow>? segments,
    List<ActionRow>? actions,
    List<ChatMessageRow>? chat,
    NoteTab? tab,
    bool? playing,
    int? positionMs,
    double? speed,
    List<double>? peaks,
    String? chatInput,
    bool? chatThinking,
    String? streamingText,
    bool clearStreaming = false,
    List<int>? streamingCites,
  }) => NoteViewState(
    note: note ?? this.note,
    ai: clearAi ? null : (ai ?? this.ai),
    segments: segments ?? this.segments,
    actions: actions ?? this.actions,
    chat: chat ?? this.chat,
    tab: tab ?? this.tab,
    playing: playing ?? this.playing,
    positionMs: positionMs ?? this.positionMs,
    speed: speed ?? this.speed,
    peaks: peaks ?? this.peaks,
    chatInput: chatInput ?? this.chatInput,
    chatThinking: chatThinking ?? this.chatThinking,
    streamingText: clearStreaming
        ? null
        : (streamingText ?? this.streamingText),
    streamingCites: streamingCites ?? this.streamingCites,
  );

  @override
  List<Object?> get props => [
    note,
    ai,
    segments,
    actions,
    chat,
    tab,
    playing,
    positionMs,
    speed,
    peaks,
    chatInput,
    chatThinking,
    streamingText,
    streamingCites,
  ];
}

/// Detalhe da nota: metadados, player (waveform/seek/velocidade) e as abas
/// Resumo/Transcrição/Insights/Conversa.
class NoteViewCubit extends Cubit<NoteViewState> {
  NoteViewCubit({
    required NoteRepository notes,
    required NoteAiRepository noteAi,
    required AiClient ai,
    required RbNative native,
    required AudioPlayerController player,
    Uuid? uuid,
  }) : _notes = notes,
       _noteAi = noteAi,
       _ai = ai,
       _native = native,
       _player = player,
       _uuid = uuid ?? const Uuid(),
       super(const NoteViewState()) {
    _posSub = _player.positionStream.listen(
      (p) => emit(state.copyWith(positionMs: p.inMilliseconds)),
    );
    _playSub = _player.playingStream.listen(
      (playing) => emit(state.copyWith(playing: playing)),
    );
  }

  final NoteRepository _notes;
  final NoteAiRepository _noteAi;
  final AiClient _ai;
  final RbNative _native;
  final AudioPlayerController _player;
  final Uuid _uuid;

  String? _noteId;
  StreamSubscription<NoteRow?>? _noteSub;
  StreamSubscription<List<SegmentRow>>? _segSub;
  StreamSubscription<NoteAi?>? _aiSub;
  StreamSubscription<List<ActionRow>>? _actionsSub;
  StreamSubscription<List<ChatMessageRow>>? _chatSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playSub;
  StreamSubscription<AiDelta>? _streamSub;

  final _notices = StreamController<String>.broadcast();
  Stream<String> get notices => _notices.stream;

  /// Carrega a nota [noteId] (resseta player, abas e assinaturas).
  Future<void> load(String noteId) async {
    if (_noteId == noteId) return;
    _noteId = noteId;
    await _cancelSubs();
    emit(
      const NoteViewState(),
    );

    _noteSub = _notes.watchNote(noteId).listen((n) {
      emit(state.copyWith(note: n));
    });
    _segSub = _notes.watchSegments(noteId).listen((s) {
      emit(state.copyWith(segments: s));
    });
    _aiSub = _noteAi.watchNoteAi(noteId).listen((ai) {
      emit(ai == null ? state.copyWith(clearAi: true) : state.copyWith(ai: ai));
    });
    _actionsSub = _noteAi.watchActions(noteId).listen((a) {
      emit(state.copyWith(actions: a));
    });
    _chatSub = _noteAi.watchChat(noteId).listen((c) {
      emit(state.copyWith(chat: c));
    });

    final note = await _notes.getNote(noteId);
    final path = note?.playbackPath;
    if (path != null) {
      unawaited(_loadPlayer(path));
      unawaited(_loadPeaks(path));
    }
  }

  Future<void> _loadPlayer(String path) async {
    try {
      await _player.load(path);
    } on Object catch (_) {
      // Demo/arquivo ausente: o waveform ainda funciona via peaks.
    }
  }

  Future<void> _loadPeaks(String path) async {
    try {
      final peaks = await _native.waveformPeaks(path, 84);
      emit(state.copyWith(peaks: peaks));
    } on Object catch (_) {
      // Sem peaks: a UI cai para um placeholder achatado.
    }
  }

  void setTab(NoteTab tab) => emit(state.copyWith(tab: tab));

  Future<void> togglePlay() async {
    if (state.playing) {
      await _player.pause();
    } else {
      if (state.positionMs >= state.durationMs && state.durationMs > 0) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  Future<void> seekTo(int ms, {bool play = false}) async {
    emit(state.copyWith(positionMs: ms));
    await _player.seek(Duration(milliseconds: ms));
    if (play) await _player.play();
  }

  /// Vai para a transcrição e toca a partir de [ms] (citações / "ouvir em").
  Future<void> jumpToTime(int ms) async {
    emit(state.copyWith(tab: NoteTab.trans));
    await seekTo(ms, play: true);
  }

  void cycleSpeed() {
    final next = switch (state.speed) {
      1.0 => 1.5,
      1.5 => 2.0,
      _ => 1.0,
    };
    emit(state.copyWith(speed: next));
  }

  Future<void> toggleAction(ActionRow action) =>
      _noteAi.setActionDone(action.id, done: !action.done);

  // ---------- chat ----------

  void setChatInput(String v) => emit(state.copyWith(chatInput: v));

  Future<void> sendChat([String? preset]) async {
    final text = (preset ?? state.chatInput).trim();
    final noteId = _noteId;
    if (text.isEmpty || noteId == null || state.chatThinking) return;

    await _noteAi.addChatMessage(
      id: _uuid.v4(),
      noteId: noteId,
      role: ChatRole.user,
      content: text,
    );
    emit(state.copyWith(chatInput: '', chatThinking: true));

    final speakers = EnrichmentSpeakers.of(state.note?.speakersJson);
    final aiSegments = _aiSegments();
    await _streamSub?.cancel();
    final buffer = StringBuffer();
    var cites = <int>[];
    _streamSub = _ai
        .chat(
          noteId: noteId,
          segments: aiSegments,
          speakers: speakers,
          message: text,
        )
        .listen(
          (delta) {
            buffer
              ..clear()
              ..write(delta.text);
            cites = delta.cites;
            emit(
              state.copyWith(
                chatThinking: false,
                streamingText: delta.text,
                streamingCites: delta.cites,
              ),
            );
          },
          onError: (Object e, StackTrace st) {
            unawaited(
              AppLogger.error(e, st, reason: 'chat', category: 'ai'),
            );
            emit(state.copyWith(chatThinking: false, clearStreaming: true));
          },
          onDone: () async {
            await _noteAi.addChatMessage(
              id: _uuid.v4(),
              noteId: noteId,
              role: ChatRole.ai,
              content: buffer.toString(),
              cites: cites,
            );
            emit(
              state.copyWith(clearStreaming: true, streamingCites: const []),
            );
          },
        );
  }

  List<AiSegment> _aiSegments() => [
    for (var i = 0; i < state.segments.length; i++)
      AiSegment(
        index: i,
        speaker: state.segments[i].speaker == SegmentSpeaker.me
            ? AiSpeaker.me
            : AiSpeaker.others,
        startMs: state.segments[i].startMs,
        endMs: state.segments[i].endMs,
        text: state.segments[i].content,
      ),
  ];

  // ---------- correção de palavra ----------

  /// Corrige [from]→[to] na nota atual ou em todas; emite um aviso (toast).
  Future<void> fixWord(
    String from,
    String to, {
    required bool everywhere,
    required bool addToVocabulary,
  }) async {
    final noteId = _noteId;
    if (noteId == null) return;
    final result = await _notes.fixWord(
      from,
      to,
      onlyNoteId: everywhere ? null : noteId,
    );
    final noun = result.notes == 1 ? 'nota' : 'notas';
    final vocab = addToVocabulary ? ' e salvo no vocabulário' : '';
    _notices.add('“$to” corrigido em ${result.notes} $noun$vocab');
  }

  /// Renomeia o título da nota atual (ação "Renomear"). Marca como título
  /// manual (não gerado pela IA).
  Future<void> renameTitle(String title) async {
    final noteId = _noteId;
    final clean = title.trim();
    if (noteId == null || clean.isEmpty) return;
    await _notes.updateTitle(noteId, clean);
  }

  Future<void> _cancelSubs() async {
    await _noteSub?.cancel();
    await _segSub?.cancel();
    await _aiSub?.cancel();
    await _actionsSub?.cancel();
    await _chatSub?.cancel();
    await _streamSub?.cancel();
  }

  @override
  Future<void> close() async {
    await _cancelSubs();
    await _posSub?.cancel();
    await _playSub?.cancel();
    await _player.dispose();
    await _notices.close();
    return super.close();
  }
}

/// Decodifica os falantes persistidos para o chat.
abstract final class EnrichmentSpeakers {
  static List<String> of(String? raw) {
    if (raw == null || raw.isEmpty) return const ['Você'];
    return raw.split('\u001f').where((s) => s.isNotEmpty).toList();
  }
}
