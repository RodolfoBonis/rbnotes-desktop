import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/auth/auth_tokens.dart';
import 'package:rbnotes/core/auth/oidc_client.dart';
import 'package:rbnotes/core/auth/token_store.dart';
import 'package:rbnotes/core/network/api_client.dart';
import 'package:rbnotes/core/network/session_events.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/data/ai_exceptions.dart';
import 'package:rbnotes/features/ai/data/api_ai_client.dart';
import 'package:rbnotes/features/ai/data/sse_client.dart';

import '../../helpers/local_server.dart';

void main() {
  late LocalServer server;

  setUp(() {
    HttpOverrides.global = null;
  });

  tearDown(() async {
    await server.close();
  });

  ApiClient apiFor() => ApiClient(
    baseUrl: '${server.base}/v1',
    tokens: MemoryTokenStore(
      const AuthTokens(accessToken: 'a', refreshToken: 'r'),
    ),
    oidc: OidcClient(
      dio: Dio(),
      issuer: '${server.base}/realms/rbnotes',
      clientId: 'rbnotes-desktop',
      redirectUri: 'http://127.0.0.1:53682/callback',
    ),
    events: SessionEvents(),
  );

  Future<void> json202(HttpRequest req, String id) async {
    req.response
      ..statusCode = 202
      ..headers.contentType = ContentType('application', 'json')
      ..write(jsonEncode({'id': id, 'status': 'queued'}));
    await req.response.close();
  }

  void sseHeaders(HttpRequest req) {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType('text', 'event-stream');
  }

  test('enrich: junta eventos json e devolve o NoteAi final', () async {
    server = await LocalServer.start((req) async {
      if (req.uri.path.endsWith('/enrich')) return json202(req, 'job1');
      sseHeaders(req);
      req.response
        ..write('event: json\ndata: {"title":"K"}\n\n')
        ..write(
          'event: json\ndata: '
          '${jsonEncode({'title': 'Kickoff', 'tldr': 'resumo'})}\n\n',
        )
        ..write('event: done\ndata: {}\n\n');
      await req.response.close();
    });

    final ai = ApiAiClient(apiFor());
    final note = await ai.enrich(
      const EnrichRequest(noteId: 'n1', segments: [], speakers: ['Você']),
    );
    expect(note.title, 'Kickoff');
    expect(note.tldr, 'resumo');
  });

  test('ask: faz streaming do texto e entrega as fontes no fim', () async {
    server = await LocalServer.start((req) async {
      if (req.uri.path.endsWith('/ask')) return json202(req, 'ask1');
      sseHeaders(req);
      req.response
        ..write('event: json\ndata: {"text":"Olh"}\n\n')
        ..write(
          'event: json\ndata: '
          '${jsonEncode({
            'text': 'Olhando',
            'sources': [
              {'noteId': 'n1', 'title': 'Nota'},
            ],
          })}\n\n',
        )
        ..write('event: done\ndata: {}\n\n');
      await req.response.close();
    });

    final ai = ApiAiClient(apiFor());
    final deltas = await ai
        .ask(question: 'e aí?', candidates: const [])
        .toList();
    expect(deltas.where((d) => !d.isDone), isNotEmpty); // streaming parcial
    expect(deltas.last.isDone, isTrue);
    expect(deltas.last.text, 'Olhando');
    expect(deltas.last.sources.single.noteId, 'n1');
  });

  test('429 ai_daily_limit → AiDailyLimitException', () async {
    server = await LocalServer.start((req) async {
      req.response
        ..statusCode = 429
        ..headers.contentType = ContentType('application', 'problem+json')
        ..write(jsonEncode({'code': 'ai_daily_limit'}));
      await req.response.close();
    });
    final ai = ApiAiClient(apiFor());
    await expectLater(
      ai.enrich(
        const EnrichRequest(noteId: 'n1', segments: [], speakers: ['Você']),
      ),
      throwsA(isA<AiDailyLimitException>()),
    );
  });

  test('reconecta com Last-Event-ID quando a stream cai', () async {
    var streamConnects = 0;
    String? lastEventIdSeen;
    server = await LocalServer.start((req) async {
      if (req.uri.path.endsWith('/ask')) return json202(req, 'recon');
      streamConnects++;
      sseHeaders(req);
      if (streamConnects == 1) {
        // Primeira conexão: um evento com id e cai sem `done`.
        req.response.write('id: 1\nevent: json\ndata: {"text":"parte1"}\n\n');
        await req.response.close();
        return;
      }
      lastEventIdSeen = req.headers.value('last-event-id');
      req.response
        ..write('event: json\ndata: {"text":"parte1-parte2"}\n\n')
        ..write('event: done\ndata: {}\n\n');
      await req.response.close();
    });

    final api = apiFor();
    final ai = ApiAiClient(
      api,
      sse: SseClient(api, retryDelay: const Duration(milliseconds: 20)),
    );
    final deltas = await ai.ask(question: 'q', candidates: const []).toList();
    expect(streamConnects, 2);
    expect(lastEventIdSeen, '1');
    expect(deltas.last.text, 'parte1-parte2');
  });
}
