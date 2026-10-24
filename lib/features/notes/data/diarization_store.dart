import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/core/paths/app_paths.dart';

/// Guarda o resultado da diarização (índiceDoSegmento → "Pessoa N") num sidecar
/// ao lado das gravações (`<id>.speakers.json`). Metadado local de exibição: o
/// Claude pode sobrescrever com nomes inferidos; se faltar, cai para "Outros".
class DiarizationStore {
  DiarizationStore(this._paths);

  final AppPaths _paths;

  String _pathFor(String noteId) =>
      p.join(_paths.recordingsDir, '$noteId.speakers.json');

  Future<void> save(String noteId, Map<int, String> labels) async {
    try {
      final file = File(_pathFor(noteId));
      if (labels.isEmpty) {
        if (file.existsSync()) await file.delete();
        return;
      }
      final json = {
        for (final e in labels.entries) e.key.toString(): e.value,
      };
      await file.writeAsString(jsonEncode(json));
    } on Object catch (e, st) {
      await AppLogger.error(e, st, reason: 'diar_save', category: 'notes');
    }
  }

  Future<Map<int, String>> load(String noteId) async {
    try {
      final file = File(_pathFor(noteId));
      if (!file.existsSync()) return const {};
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return const {};
      return {
        for (final e in raw.entries)
          if (int.tryParse(e.key as String) != null && e.value is String)
            int.parse(e.key as String): e.value as String,
      };
    } on Object catch (e, st) {
      await AppLogger.error(e, st, reason: 'diar_load', category: 'notes');
      return const {};
    }
  }
}
