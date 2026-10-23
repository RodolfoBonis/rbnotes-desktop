import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Redação de PII/segredos antes de escrever qualquer coisa no log em arquivo.
///
/// O log em release vai para o disco do usuário, então nunca pode conter
/// tokens nem dados pessoais. Esta função mascara os padrões mais arriscados
/// (JWTs, `Authorization: Bearer`, e-mails, `*_token=...`). O app, por
/// convenção, já não registra o conteúdo das notas nem caminhos de arquivos.
abstract final class LogRedaction {
  static final _jwt = RegExp(
    r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',
  );
  static final _bearer = RegExp(r'[Bb]earer\s+[A-Za-z0-9._-]+');
  static final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');
  static final _token = RegExp(
    '(access_token|refresh_token|id_token|token|password|secret|code)'
    r'["\s:=]+[^\s",}&]+',
    caseSensitive: false,
  );

  static String apply(String input) {
    return input
        .replaceAll(_jwt, '***jwt***')
        .replaceAll(_bearer, 'Bearer ***')
        .replaceAll(_email, '***@***')
        .replaceAllMapped(_token, (m) => '${m[1]}=***');
  }

  static Object? value(Object? v) =>
      v is String ? apply(v) : (v == null ? null : apply(v.toString()));
}

/// Sink de log em arquivo JSON-lines com rotação.
///
/// Uma linha JSON por evento (nível ≥ info). Rotaciona quando o arquivo passa
/// de [maxBytes] (5 MB por padrão), mantendo [maxBackups] cópias
/// (`rbnotes.log.1`, `.2`). As escritas são serializadas numa fila (Future
/// encadeado) para não bloquear a UI nem corromper o arquivo, e qualquer falha
/// de IO é engolida — logar nunca pode derrubar o app.
class FileLogSink {
  FileLogSink({
    required this.file,
    this.maxBytes = 5 * 1024 * 1024,
    this.maxBackups = 2,
  });

  /// Abre o sink em [logsDir] (criando a pasta). Retorna null se não der para
  /// escrever ali (ex.: permissão) — nesse caso o app segue só com Sentry.
  static Future<FileLogSink?> open(Directory logsDir) async {
    try {
      await logsDir.create(recursive: true);
      final sink = FileLogSink(file: File(p.join(logsDir.path, 'rbnotes.log')));
      // Toque de verificação: se não der para escrever, caímos no catch.
      if (!sink.file.existsSync()) {
        await sink.file.create(recursive: true);
      }
      return sink;
    } on Object {
      return null;
    }
  }

  final File file;
  final int maxBytes;
  final int maxBackups;

  Future<void> _tail = Future<void>.value();

  /// Enfileira a escrita de um registro (já redigido). Non-blocking.
  void write(Map<String, Object?> record) {
    final line = jsonEncode(record);
    _tail = _tail.then((_) => _append(line)).catchError((Object _) {});
  }

  /// Espera a fila drenar (para testes).
  Future<void> flush() => _tail;

  Future<void> _append(String line) async {
    await _rotateIfNeeded();
    await file.writeAsString(
      '$line\n',
      mode: FileMode.writeOnlyAppend,
      flush: true,
    );
  }

  Future<void> _rotateIfNeeded() async {
    if (!file.existsSync()) return;
    if (await file.length() < maxBytes) return;
    // Remove o backup mais antigo e desloca os demais: .1 -> .2, log -> .1.
    final oldest = File('${file.path}.$maxBackups');
    if (oldest.existsSync()) await oldest.delete();
    for (var i = maxBackups - 1; i >= 1; i--) {
      final src = File('${file.path}.$i');
      if (src.existsSync()) await src.rename('${file.path}.${i + 1}');
    }
    if (maxBackups >= 1) {
      await file.rename('${file.path}.1');
    } else {
      await file.delete();
    }
  }
}
