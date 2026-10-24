import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/network/api_error.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/local_data_wiper.dart';
import 'package:rbnotes/features/sync/data/audio_sync.dart';
import 'package:rbnotes/features/sync/data/sync_local_store.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';

/// Resultado de "Apagar todos os dados".
enum EraseResult {
  /// Tudo apagado localmente e na nuvem.
  done,

  /// Apagado só localmente, sem contato com a nuvem (via `finishLocalOnly`).
  doneLocalOnly,

  /// Offline no push: os tombstones foram marcados, mas nada foi limpo ainda.
  /// O chamador decide: `finishLocalOnly` (apaga local) ou aguardar.
  offlinePending,
}

/// Progresso de uma etapa de "Apagar todos os dados".
class EraseProgress extends Equatable {
  const EraseProgress({
    required this.step,
    required this.total,
    required this.label,
  });

  final int step;
  final int total;
  final String label;

  @override
  List<Object?> get props => [step, total, label];
}

/// Orquestra "Apagar todos os dados" na ordem do plano da Fase 3:
///
/// 1. soft-delete de todas as entidades (tombstones);
/// 2. push (envia os tombstones ao servidor);
/// 3. `DELETE /notes/{id}/audio` para cada nota com áudio;
/// 4. limpeza local (banco, arquivos, caches, fila de áudio);
/// 5. reset do cursor (feito dentro da limpeza local via `LocalDataWiper`).
///
/// Offline no passo 2: devolve [EraseResult.offlinePending] (sem limpar nada);
/// o chamador mostra o aviso e, se confirmado, chama [finishLocalOnly]. Sem
/// backend (local-first), pula 1–3 e faz só a limpeza local.
class EraseAllService {
  EraseAllService({
    required NoteRepository notes,
    required SyncLocalStore store,
    required LocalDataWiper wiper,
    this.sync,
    this.audio,
  }) : _notes = notes,
       _store = store,
       _wiper = wiper;

  final NoteRepository _notes;
  final SyncLocalStore _store;
  final LocalDataWiper _wiper;
  final SyncService? sync;
  final AudioSync? audio;

  Future<EraseResult> eraseAll({
    void Function(EraseProgress progress)? onProgress,
  }) async {
    final hasBackend = sync != null;
    final total = hasBackend ? 4 : 1;
    var step = 0;
    void emit(String label) => onProgress?.call(
      EraseProgress(step: ++step, total: total, label: label),
    );

    if (!hasBackend) {
      emit('Apagando os dados deste Mac');
      await _wiper.wipe();
      return EraseResult.done;
    }

    // Ids com áudio, coletados antes de limpar o banco.
    final notesWithAudio = <String>[
      for (final n in await _notes.getAllNotes())
        if (n.playbackPath != null ||
            n.micWavPath != null ||
            n.systemWavPath != null)
          n.id,
    ];

    emit('Marcando tudo para exclusão');
    await _store.softDeleteAll();

    emit('Enviando as exclusões');
    try {
      await sync!.pushNow();
    } on ApiError catch (e) {
      if (e.isNetwork) return EraseResult.offlinePending;
      rethrow;
    }

    emit('Apagando os áudios na nuvem');
    for (final id in notesWithAudio) {
      try {
        await audio?.deleteAudio(id);
      } on ApiError catch (e) {
        // Melhor-esforço: um áudio que não apagou não bloqueia a limpeza.
        AppLogger.warning(
          'Falha ao apagar áudio na nuvem',
          category: 'privacy',
          error: e,
        );
      }
    }

    emit('Apagando os dados deste Mac');
    await _wiper.wipe();
    return EraseResult.done;
  }

  /// Limpa só os dados locais (após `EraseResult.offlinePending`, se o dono
  /// escolher apagar mesmo offline). Os tombstones sobem no próximo sync.
  Future<EraseResult> finishLocalOnly({
    void Function(EraseProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const EraseProgress(
        step: 1,
        total: 1,
        label: 'Apagando os dados deste Mac',
      ),
    );
    await _wiper.wipe();
    return EraseResult.doneLocalOnly;
  }
}
