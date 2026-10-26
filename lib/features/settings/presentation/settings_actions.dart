import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/core/ui/task_progress_dialog.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/auth/data/auth_service.dart';
import 'package:rbnotes/features/notes/data/export_service.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/security/data/biometric_auth.dart';
import 'package:rbnotes/features/settings/data/erase_all_service.dart';
import 'package:rbnotes/features/settings/data/local_data_wiper.dart';
import 'package:rbnotes/features/settings/presentation/erase_progress_dialog.dart';
import 'package:rbnotes/features/sync/data/audio_sync.dart';
import 'package:rbnotes/features/sync/data/audio_upload_queue.dart';
import 'package:rbnotes/features/sync/data/sync_crypto.dart';
import 'package:rbnotes/features/sync/data/sync_local_store.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';

/// Destructive / long-running account & data flows triggered from Settings.
///
/// These used to live in the shell when Settings was an in-window modal; now
/// that Settings is its own native window they run in that window's context
/// (its [Navigator] shows the progress dialogs) and report back through an
/// [onToast] callback instead of the shell's `ShellOverlayCubit`.

/// "Exportar todas as notas": destination picker, progress and Touch ID for the
/// locked notes.
Future<void> exportAllNotes(
  BuildContext context, {
  required void Function(String message) onToast,
}) async {
  final nav = Navigator.of(context, rootNavigator: true);

  final location = await getSaveLocation(
    suggestedName: 'rbnotes-export.zip',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Zip', extensions: ['zip']),
    ],
  );
  final path = location?.path;
  if (path == null) return;

  final message = ValueNotifier<String>('Preparando…');
  final progress = ValueNotifier<double?>(null);
  if (!nav.mounted) {
    message.dispose();
    progress.dispose();
    return;
  }
  unawaited(
    showDialog<void>(
      context: nav.context,
      barrierDismissible: false,
      builder: (_) => TaskProgressDialog(
        title: 'Exportando notas',
        message: message,
        progress: progress,
      ),
    ),
  );

  final service = ExportService(notes: di<NoteRepository>());
  final biometric = di<BiometricAuth>();
  try {
    final result = await service.exportAll(
      destinationPath: path,
      onProgress: (done, total) {
        message.value = 'Exportando $done de $total…';
        progress.value = total == 0 ? null : done / total;
      },
      unlockLocked: () =>
          biometric.authenticate('Desbloquear notas para exportar'),
    );
    if (nav.canPop()) nav.pop();
    final extra = result.excludedLocked > 0
        ? ' (${result.excludedLocked} bloqueada'
              '${result.excludedLocked == 1 ? '' : 's'} ficaram de fora)'
        : '';
    onToast('Exportadas ${result.exported} notas$extra.');
  } on Object catch (e, st) {
    if (nav.canPop()) nav.pop();
    await AppLogger.error(e, st, reason: 'export_all', category: 'notes');
    onToast('Não foi possível exportar as notas.');
  } finally {
    message.dispose();
    progress.dispose();
  }
}

/// Builds the local-data wiper from the DI container.
LocalDataWiper buildLocalDataWiper() => LocalDataWiper(
  db: di<AppDatabase>(),
  notes: di<NoteRepository>(),
  paths: di<AppPaths>(),
  sync: di.isRegistered<SyncService>() ? di<SyncService>() : null,
  audioQueue: di.isRegistered<AudioUploadQueue>()
      ? di<AudioUploadQueue>()
      : null,
);

/// "Apagar dados locais" do logout: banco, cursor/marca d'água, fila de áudio e
/// os caches de áudio (recordings + audio_cache).
Future<void> wipeLocalData() => buildLocalDataWiper().wipe();

/// "Apagar todos os dados" da aba Privacidade, com progresso. Ordem: tombstones
/// → push → DELETE do áudio na nuvem → limpeza local → reset do cursor. Offline
/// no push: oferece apagar só neste Mac, com aviso.
Future<void> eraseAllData(
  BuildContext context, {
  required void Function(String message) onToast,
  required VoidCallback closeSettings,
}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final progress = ValueNotifier<EraseProgress?>(null);
  final service = EraseAllService(
    notes: di<NoteRepository>(),
    store: SyncLocalStore(
      di<AppDatabase>(),
      crypto: di.isRegistered<SyncCrypto>() ? di<SyncCrypto>() : null,
    ),
    wiper: buildLocalDataWiper(),
    sync: di.isRegistered<SyncService>() ? di<SyncService>() : null,
    audio: di.isRegistered<AudioSync>() ? di<AudioSync>() : null,
  );

  void openProgress() => unawaited(
    showDialog<void>(
      context: nav.context,
      barrierDismissible: false,
      builder: (_) => EraseProgressDialog(progress: progress),
    ),
  );

  openProgress();
  var result = await service.eraseAll(onProgress: (p) => progress.value = p);

  if (result == EraseResult.offlinePending) {
    if (nav.canPop()) nav.pop();
    if (!nav.mounted) {
      progress.dispose();
      return;
    }
    final goLocal = await showDialog<bool>(
      context: nav.context,
      builder: (ctx) => AlertDialog(
        title: const Text('Você está offline'),
        content: const Text(
          'Não consegui falar com o servidor agora. Posso apagar os dados '
          'deste Mac mesmo assim — a exclusão na nuvem acontece quando você '
          'reconectar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Aguardar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: RbTokens.destructive),
            child: const Text('Apagar só neste Mac'),
          ),
        ],
      ),
    );
    if (goLocal ?? false) {
      progress.value = null;
      openProgress();
      result = await service.finishLocalOnly(
        onProgress: (p) => progress.value = p,
      );
    } else {
      progress.dispose();
      closeSettings();
      onToast('Exclusão adiada — você está offline.');
      return;
    }
  }

  if (nav.canPop()) nav.pop();
  progress.dispose();
  closeSettings();
  if (result == EraseResult.doneLocalOnly) {
    onToast('Dados apagados neste Mac. A nuvem será limpa depois.');
  }
  await di<AuthService>().signOut();
}
