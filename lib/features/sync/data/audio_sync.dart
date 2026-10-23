import 'dart:io';
import 'dart:typed_data';

import 'package:rbnotes/core/network/api_client.dart';
import 'package:rbnotes/core/network/api_error.dart';

/// Upload/download do áudio das notas conforme o contrato (`/notes/{id}/audio`).
///
/// Chunk de **16 MiB** (padrão e máximo); toda parte **não final** tem 16 MiB
/// (≥ 5 MiB exigidos pelo multipart S3) e só a última pode ser menor. A parte 1
/// vai primeiro. Reenviar a última parte após concluir é idempotente.
class AudioSync {
  AudioSync(this._api);

  final ApiClient _api;

  static const int chunkSize = 16 * 1024 * 1024;
  static const int minNonFinalPart = 5 * 1024 * 1024;

  /// Nº de partes de um conteúdo de [length] bytes.
  static int partsFor(int length) {
    if (length <= 0) return 1;
    return (length / chunkSize).ceil();
  }

  /// Faz upload de um arquivo. Retoma a partir de [startPart] (1-based). Se o
  /// servidor indicar que o upload não existe (`409 audio_no_upload`), recomeça
  /// da parte 1.
  Future<void> uploadFile(
    String noteId,
    String filePath, {
    int startPart = 1,
    String contentType = 'audio/mp4',
  }) async {
    final bytes = await File(filePath).readAsBytes();
    await uploadBytes(
      noteId,
      bytes,
      startPart: startPart,
      contentType: contentType,
    );
  }

  /// Upload a partir de bytes em memória (usado nos testes e por [uploadFile]).
  Future<void> uploadBytes(
    String noteId,
    Uint8List bytes, {
    int startPart = 1,
    String contentType = 'audio/mp4',
  }) async {
    final total = partsFor(bytes.length);
    var part = startPart.clamp(1, total);
    while (part <= total) {
      final start = (part - 1) * chunkSize;
      final end = (start + chunkSize).clamp(0, bytes.length);
      final chunk = bytes.sublist(start, end);
      try {
        final res = await _api.putBytes(
          '/notes/$noteId/audio',
          bytes: chunk,
          query: {'part': part, 'total': total},
          contentType: contentType,
        );
        final completed = (res['completed'] as bool?) ?? false;
        if (completed) return;
        part++;
      } on ApiError catch (e) {
        // Upload perdido no servidor: recomeça da parte 1.
        if (e.isConflict && e.code == 'audio_no_upload' && part > 1) {
          part = 1;
          continue;
        }
        rethrow;
      }
    }
  }

  /// Baixa o áudio para [destPath] com retomada via `Range` (continua de
  /// onde o arquivo local parou). Retorna o total de bytes do arquivo final.
  Future<int> downloadToFile(String noteId, String destPath) async {
    final file = File(destPath);
    await file.parent.create(recursive: true);
    var existing = file.existsSync() ? await file.length() : 0;

    final first = await _api.getBytes(
      '/notes/$noteId/audio',
      rangeStart: existing > 0 ? existing : null,
    );
    if (first.statusCode == 200) {
      // Servidor ignorou o Range (ou não havia parcial): grava do zero.
      await file.writeAsBytes(first.bytes);
      existing = first.bytes.length;
    } else {
      await file.writeAsBytes(first.bytes, mode: FileMode.append);
      existing += first.bytes.length;
    }

    final total = first.totalLength;
    while (total != null && existing < total) {
      final next = await _api.getBytes(
        '/notes/$noteId/audio',
        rangeStart: existing,
      );
      if (next.bytes.isEmpty) break;
      await file.writeAsBytes(next.bytes, mode: FileMode.append);
      existing += next.bytes.length;
      if (next.statusCode == 200) break;
    }
    return existing;
  }
}
