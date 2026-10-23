import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/auth/auth_tokens.dart';
import 'package:rbnotes/core/auth/oidc_client.dart';
import 'package:rbnotes/core/auth/token_store.dart';
import 'package:rbnotes/core/network/api_client.dart';
import 'package:rbnotes/core/network/api_error.dart';
import 'package:rbnotes/core/network/session_events.dart';
import 'package:rbnotes/features/sync/data/audio_sync.dart';

import '../../helpers/local_server.dart';

void main() {
  LocalServer? server;

  setUp(() {
    HttpOverrides.global = null;
  });

  tearDown(() async {
    await server?.close();
  });

  AudioSync audioFor() {
    final api = ApiClient(
      baseUrl: '${server!.base}/v1',
      tokens: MemoryTokenStore(
        const AuthTokens(accessToken: 'a', refreshToken: 'r'),
      ),
      oidc: OidcClient(
        dio: Dio(),
        issuer: '${server!.base}/realms/rbnotes',
        clientId: 'rbnotes-desktop',
        redirectUri: 'http://127.0.0.1:53682/callback',
      ),
      events: SessionEvents(),
    );
    return AudioSync(api);
  }

  test('partsFor respeita o chunk de 16 MiB', () {
    expect(AudioSync.partsFor(0), 1);
    expect(AudioSync.partsFor(1), 1);
    expect(AudioSync.partsFor(AudioSync.chunkSize), 1);
    expect(AudioSync.partsFor(AudioSync.chunkSize + 1), 2);
  });

  test('upload em partes: parte 1 primeiro, não-final ≥ 5 MiB', () async {
    final received = <(int, int, int)>[]; // (part, total, length)
    server = await LocalServer.start((req) async {
      final part = int.parse(req.uri.queryParameters['part']!);
      final total = int.parse(req.uri.queryParameters['total']!);
      received.add((part, total, req.contentLength));
      await req.drain<void>();
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('application', 'json')
        ..write(jsonEncode({'part': part, 'completed': part == total}));
      await req.response.close();
    });

    final bytes = Uint8List(AudioSync.chunkSize + 100);
    await audioFor().uploadBytes('n1', bytes);

    expect(received, hasLength(2));
    expect(received[0].$1, 1); // parte 1 primeiro
    expect(received[0].$3, AudioSync.chunkSize); // não-final = 16 MiB (≥ 5 MiB)
    expect(received[0].$3, greaterThanOrEqualTo(AudioSync.minNonFinalPart));
    expect(received[1].$1, 2);
    expect(received[1].$3, 100); // última pode ser menor
  });

  test('retoma do 1 quando o servidor responde 409 audio_no_upload', () async {
    final seen = <int>[];
    var started = false;
    server = await LocalServer.start((req) async {
      final part = int.parse(req.uri.queryParameters['part']!);
      final total = int.parse(req.uri.queryParameters['total']!);
      seen.add(part);
      await req.drain<void>();
      if (part > 1 && !started) {
        req.response
          ..statusCode = 409
          ..headers.contentType = ContentType('application', 'problem+json')
          ..write(jsonEncode({'code': 'audio_no_upload'}));
        await req.response.close();
        return;
      }
      if (part == 1) started = true;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('application', 'json')
        ..write(jsonEncode({'part': part, 'completed': part == total}));
      await req.response.close();
    });

    final bytes = Uint8List(AudioSync.chunkSize + 100);
    await audioFor().uploadBytes('n1', bytes, startPart: 2);
    expect(seen, [2, 1, 2]); // 409 na 2, reinicia na 1, conclui na 2
  });

  test('download com Range retoma de onde o arquivo parou', () async {
    final full = List<int>.generate(10, (i) => i);
    server = await LocalServer.start((req) async {
      final range = req.headers.value('range');
      req.response.headers.set('accept-ranges', 'bytes');
      if (range == null) {
        req.response.statusCode = 200;
        req.response.add(full);
      } else {
        final start = int.parse(
          RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!,
        );
        req.response
          ..statusCode = 206
          ..headers.set('content-range', 'bytes $start-9/10')
          ..add(full.sublist(start));
      }
      await req.response.close();
    });

    final dir = await Directory.systemTemp.createTemp('rbnotes_audio');
    addTearDown(() => dir.deleteSync(recursive: true));
    final dest = '${dir.path}/n1.m4a';
    await File(dest).writeAsBytes([0, 1, 2, 3]); // parcial de 4 bytes

    final size = await audioFor().downloadToFile('n1', dest);
    expect(size, 10);
    expect(await File(dest).readAsBytes(), full);
  });

  test('download em blocos reporta progresso e conclui', () async {
    final full = List<int>.generate(10, (i) => i);
    server = await LocalServer.start((req) async {
      final range = req.headers.value('range')!;
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
      final start = int.parse(m.group(1)!);
      final endRaw = m.group(2)!;
      var end = endRaw.isEmpty ? full.length - 1 : int.parse(endRaw);
      if (end >= full.length) end = full.length - 1;
      req.response
        ..statusCode = 206
        ..headers.set('content-range', 'bytes $start-$end/${full.length}')
        ..add(full.sublist(start, end + 1));
      await req.response.close();
    });

    final dir = await Directory.systemTemp.createTemp('rbnotes_audio_dl');
    addTearDown(() => dir.deleteSync(recursive: true));
    final dest = '${dir.path}/n1.m4a';
    final progress = <double>[];
    final size = await audioFor().downloadToFile(
      'n1',
      dest,
      chunk: 4,
      onProgress: (received, total) {
        if (total != null && total > 0) progress.add(received / total);
      },
    );

    expect(size, 10);
    expect(await File(dest).readAsBytes(), full);
    expect(progress.first, lessThan(1.0));
    expect(progress.last, 1.0);
    expect(progress.length, greaterThan(1), reason: 'baixou em vários blocos');
  });

  test('download 404 → ApiError.isNotFound (áudio indisponível)', () async {
    server = await LocalServer.start((req) async {
      req.response.statusCode = 404;
      await req.response.close();
    });
    final dir = await Directory.systemTemp.createTemp('rbnotes_audio_404');
    addTearDown(() => dir.deleteSync(recursive: true));

    await expectLater(
      audioFor().downloadToFile('n1', '${dir.path}/n1.m4a'),
      throwsA(isA<ApiError>().having((e) => e.isNotFound, 'isNotFound', true)),
    );
    expect(File('${dir.path}/n1.m4a').existsSync(), isFalse);
  });
}
