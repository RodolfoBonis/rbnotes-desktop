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

  // Monta um evento SSE no formato REAL do servidor: o campo `data:` é sempre o
  // envelope `{"data":"<conteúdo>","code"?:"<código>"}`. [inner] é o conteúdo
  // real (um pedaço de JSON nos `json`, o JSON completo no `done`).
  String sse(String event, String inner, {String? code, String? id}) {
    final env = <String, dynamic>{
      'data': inner,
      'code': ?code,
    };
    final prefix = id == null ? '' : 'id: $id\n';
    return '${prefix}event: $event\ndata: ${jsonEncode(env)}\n\n';
  }

  test(
    'enrich: o resultado final vem do done (envelope desembrulhado)',
    () async {
      server = await LocalServer.start((req) async {
        if (req.uri.path.endsWith('/enrich')) return json202(req, 'job1');
        sseHeaders(req);
        req.response
          ..write(sse('json', '{"title":"Kic'))
          ..write(sse('json', 'koff","tldr":"resumo"}'))
          ..write(
            sse('done', '{"title":"Kickoff","tldr":"resumo","points":["p"]}'),
          );
        await req.response.close();
      });

      final ai = ApiAiClient(apiFor());
      final note = await ai.enrich(
        const EnrichRequest(noteId: 'n1', segments: [], speakers: ['Você']),
      );
      expect(note.title, 'Kickoff');
      expect(note.tldr, 'resumo');
      expect(note.points, ['p']);
    },
  );

  test(
    'enrich: done vazio → fallback para o buffer dos json parciais',
    () async {
      server = await LocalServer.start((req) async {
        if (req.uri.path.endsWith('/enrich')) return json202(req, 'job2');
        sseHeaders(req);
        req.response
          ..write(sse('json', '{"title":"Kickoff",'))
          ..write(sse('json', '"tldr":"resumo"}'))
          ..write(sse('done', '')); // servidor antigo: done sem resultado
        await req.response.close();
      });

      final ai = ApiAiClient(apiFor());
      final note = await ai.enrich(
        const EnrichRequest(noteId: 'n1', segments: [], speakers: ['Você']),
      );
      expect(note.title, 'Kickoff');
      expect(note.tldr, 'resumo');
    },
  );

  test(
    'enrich: envelope nunca é tratado como resultado (bug corrigido)',
    () async {
      // Reproduz o SSE real que gerava note_ai {}: cada evento é um envelope.
      // Se o cliente tratasse o envelope como objeto, o título viria vazio.
      server = await LocalServer.start((req) async {
        if (req.uri.path.endsWith('/enrich')) return json202(req, 'job3');
        sseHeaders(req);
        req.response
          ..write(sse('json', '{"title":"Reuniao","tldr":"ok"}'))
          ..write(sse('done', '{"title":"Reuniao","tldr":"ok"}'));
        await req.response.close();
      });

      final ai = ApiAiClient(apiFor());
      final note = await ai.enrich(
        const EnrichRequest(noteId: 'n1', segments: [], speakers: ['Você']),
      );
      expect(note.title, 'Reuniao');
      expect(note.tldr, 'ok');
    },
  );

  test(
    'ask: faz streaming do texto parcial e entrega as fontes no fim',
    () async {
      server = await LocalServer.start((req) async {
        if (req.uri.path.endsWith('/ask')) return json202(req, 'ask1');
        sseHeaders(req);
        req.response
          ..write(sse('json', '{"text":"Olh'))
          ..write(
            sse('json', 'ando","sources":[{"noteId":"n1","title":"Nota"}]}'),
          )
          ..write(
            sse(
              'done',
              '{"text":"Olhando","sources":[{"noteId":"n1","title":"Nota"}]}',
            ),
          );
        await req.response.close();
      });

      final ai = ApiAiClient(apiFor());
      final deltas = await ai
          .ask(question: 'e aí?', candidates: const [])
          .toList();
      final partial = deltas.where((d) => !d.isDone).toList();
      expect(partial, isNotEmpty); // streaming parcial via parse tolerante
      expect(partial.first.text, 'Olh');
      expect(deltas.last.isDone, isTrue);
      expect(deltas.last.text, 'Olhando');
      expect(deltas.last.sources.single.noteId, 'n1');
    },
  );

  test('erro: o envelope de error vira AiException com a mensagem', () async {
    server = await LocalServer.start((req) async {
      if (req.uri.path.endsWith('/enrich')) return json202(req, 'joberr');
      sseHeaders(req);
      req.response.write(
        sse('error', 'A IA nao conseguiu responder.', code: 'stream_timeout'),
      );
      await req.response.close();
    });

    final ai = ApiAiClient(apiFor());
    await expectLater(
      ai.enrich(
        const EnrichRequest(noteId: 'n1', segments: [], speakers: ['Você']),
      ),
      throwsA(
        isA<AiException>().having(
          (e) => e.message,
          'message',
          'A IA nao conseguiu responder.',
        ),
      ),
    );
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
        req.response.write(sse('json', '{"text":"parte1"}', id: '1'));
        await req.response.close();
        return;
      }
      lastEventIdSeen = req.headers.value('last-event-id');
      req.response
        ..write(sse('json', '{"text":"parte1-parte2"}'))
        ..write(sse('done', '{"text":"parte1-parte2"}'));
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
