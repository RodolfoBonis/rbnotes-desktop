import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/domain/note_export.dart';

/// Resultado de "Exportar todas as notas".
class ExportResult extends Equatable {
  const ExportResult({required this.exported, required this.excludedLocked});

  /// Notas escritas no .zip.
  final int exported;

  /// Notas bloqueadas deixadas de fora (Touch ID negado/cancelado).
  final int excludedLocked;

  @override
  List<Object?> get props => [exported, excludedLocked];
}

/// Exporta todas as notas para um `.zip` (método "store", sem compressão) com
/// uma pasta por nota contendo `nota.md` e, opcionalmente, o áudio.
///
/// Notas bloqueadas exigem Touch ID antes de entrar; se o desbloqueio falhar
/// ou for cancelado, elas ficam de fora e o total é reportado em
/// [ExportResult.excludedLocked] para a UI avisar.
class ExportService {
  ExportService({required NoteRepository notes}) : _notes = notes;

  final NoteRepository _notes;

  Future<ExportResult> exportAll({
    required String destinationPath,
    void Function(int done, int total)? onProgress,
    Future<bool> Function()? unlockLocked,
  }) async {
    final all = await _notes.getAllNotes();
    final locked = all.where((n) => n.locked).toList();

    var includeLocked = locked.isEmpty;
    if (locked.isNotEmpty && unlockLocked != null) {
      includeLocked = await unlockLocked();
    }

    final included = includeLocked ? all : all.where((n) => !n.locked).toList();

    final entries = <ZipEntry>[];
    final usedFolders = <String>{};
    var done = 0;
    for (final note in included) {
      final segments = await _notes.getSegments(note.id);
      final tags = await _notes.getNoteTags(note.id);
      final folder = _uniqueFolder(note, usedFolders);

      entries.add((
        name: '$folder/nota.md',
        bytes: utf8.encode(noteMarkdown(note, segments, tags)),
      ));

      final audio = note.playbackPath;
      if (audio != null && File(audio).existsSync()) {
        entries.add((
          name: '$folder/audio.m4a',
          bytes: await File(audio).readAsBytes(),
        ));
      }

      done++;
      onProgress?.call(done, included.length);
    }

    final zipBytes = buildZip(entries);
    await File(destinationPath).writeAsBytes(zipBytes);

    return ExportResult(
      exported: included.length,
      excludedLocked: includeLocked ? 0 : locked.length,
    );
  }

  String _uniqueFolder(NoteRow note, Set<String> used) {
    final base = _slug(note.title);
    var name = base;
    var i = 2;
    while (used.contains(name)) {
      name = '$base-$i';
      i++;
    }
    used.add(name);
    return name;
  }

  static const _accents = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };

  static String _slug(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return 'sem-titulo';
    final buffer = StringBuffer();
    for (final ch in trimmed.toLowerCase().split('')) {
      buffer.write(_accents[ch] ?? ch);
    }
    final slug = buffer
        .toString()
        .replaceAll(RegExp('[^a-z0-9 ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    final clipped = slug.length > 60 ? slug.substring(0, 60) : slug;
    return clipped.isEmpty ? 'sem-titulo' : clipped;
  }
}
