import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rbnotes/core/observability/file_log_sink.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('rbnotes_logs'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('LogRedaction', () {
    test('mascara JWT, Bearer, e-mail e tokens', () {
      expect(
        LogRedaction.apply('Authorization: Bearer abc.def-123'),
        contains('Bearer ***'),
      );
      expect(
        LogRedaction.apply('header eyJhbGciOi.JIUzI1NiIsI.nR5cC16IkpXVCJ9'),
        contains('***jwt***'),
      );
      expect(LogRedaction.apply('user joao@exemplo.com'), contains('***@***'));
      final r = LogRedaction.apply('access_token=segredoLongo123');
      expect(r.contains('segredoLongo123'), isFalse);
    });
  });

  group('FileLogSink', () {
    test('escreve JSON lines e redige o conteudo', () async {
      final sink = (await FileLogSink.open(tmp))!
        ..write({'level': 'info', 'msg': LogRedaction.apply('x joao@y.com')});
      await sink.flush();
      final file = File(p.join(tmp.path, 'rbnotes.log'));
      final lines = file.readAsLinesSync();
      expect(lines, hasLength(1));
      final decoded = jsonDecode(lines.first) as Map<String, dynamic>;
      expect(decoded['level'], 'info');
      expect(decoded['msg'], contains('***@***'));
    });

    test('rotaciona ao passar de maxBytes mantendo backups', () async {
      final sink = FileLogSink(
        file: File(p.join(tmp.path, 'rbnotes.log')),
        maxBytes: 200,
      );
      for (var i = 0; i < 60; i++) {
        sink.write({'i': i, 'pad': 'x' * 20});
      }
      await sink.flush();
      expect(File(p.join(tmp.path, 'rbnotes.log')).existsSync(), isTrue);
      expect(File(p.join(tmp.path, 'rbnotes.log.1')).existsSync(), isTrue);
      // Nunca mantem mais que maxBackups backups.
      expect(File(p.join(tmp.path, 'rbnotes.log.3')).existsSync(), isFalse);
    });
  });
}
