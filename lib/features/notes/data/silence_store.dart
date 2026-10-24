import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/native/rb_native.dart';

/// Guarda os intervalos de silêncio de uma nota num arquivo sidecar ao lado das
/// gravações (`<id>.silences.json`), sem reescrever o áudio. Metadado local de
/// reprodução: não sincroniza nem é essencial — se faltar, o player toca tudo.
class SilenceStore {
  SilenceStore(this._paths);

  final AppPaths _paths;

  String _pathFor(String noteId) =>
      p.join(_paths.recordingsDir, '$noteId.silences.json');

  /// Salva os intervalos (em ms). Lista vazia apaga o sidecar.
  Future<void> save(String noteId, List<SilenceRange> ranges) async {
    try {
      final file = File(_pathFor(noteId));
      if (ranges.isEmpty) {
        if (file.existsSync()) await file.delete();
        return;
      }
      final json = [
        for (final r in ranges)
          {'s': r.start.inMilliseconds, 'e': r.end.inMilliseconds},
      ];
      await file.writeAsString(jsonEncode(json));
    } on Object catch (e, st) {
      await AppLogger.error(e, st, reason: 'silence_save', category: 'notes');
    }
  }

  /// Lê os intervalos salvos; vazio se não houver sidecar ou falhar.
  Future<List<(int start, int end)>> load(String noteId) async {
    try {
      final file = File(_pathFor(noteId));
      if (!file.existsSync()) return const [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (item is Map && item['s'] is num && item['e'] is num)
            ((item['s'] as num).toInt(), (item['e'] as num).toInt()),
      ];
    } on Object catch (e, st) {
      await AppLogger.error(e, st, reason: 'silence_load', category: 'notes');
      return const [];
    }
  }
}
