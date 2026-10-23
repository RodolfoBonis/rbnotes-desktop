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

  /// Baixa o áudio para [destPath] em blocos de [chunk] bytes, com retomada via
  /// `Range` (continua do que já há em disco) e [onProgress] por bloco
  /// (`received`, `total`). Baixar em blocos limita o uso de memória e permite
  /// mostrar progresso. Retorna o total de bytes do arquivo final.
  ///
  /// Propaga [ApiError] (ex.: `404` → áudio ainda não existe no servidor) para
  /// o chamador tratar.
  Future<int> downloadToFile(
    String noteId,
    String destPath, {
    int chunk = chunkSize,
    void Function(int received, int? total)? onProgress,
  }) async {
    final file = File(destPath);
    await file.parent.create(recursive: true);
    var existing = file.existsSync() ? await file.length() : 0;
    int? total;

    while (true) {
      final res = await _api.getBytes(
        '/notes/$noteId/audio',
        rangeStart: existing,
        rangeEnd: existing + chunk - 1,
      );

      if (res.statusCode == 200) {
        // Servidor ignorou o Range: o corpo é o arquivo inteiro.
        await file.writeAsBytes(res.bytes);
        existing = res.bytes.length;
        total = res.totalLength ?? existing;
        onProgress?.call(existing, total);
        break;
      }

      // 206 Partial Content.
      if (existing == 0) {
        await file.writeAsBytes(res.bytes);
      } else {
        await file.writeAsBytes(res.bytes, mode: FileMode.append);
      }
      existing += res.bytes.length;
      total = res.totalLength ?? total;
      onProgress?.call(existing, total);

      if (res.bytes.isEmpty) break;
      if (total != null && existing >= total) break;
    }
    return existing;
  }
}
