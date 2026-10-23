import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:rbnotes/core/network/api_client.dart';

/// Um evento SSE decodificado (`event`, `data` concatenado, `id`).
class SseEvent {
  const SseEvent({required this.event, required this.data, this.id});

  final String event;
  final String data;
  final String? id;

  bool get isDone => event == 'done';
  bool get isError => event == 'error';
}

/// Decodificador de `text/event-stream` incremental: alimente os chunks de texto
/// e receba os eventos completos. Lida com linhas partidas entre chunks, `\r\n`,
/// comentários (`:`), e os campos `event`/`data`/`id` (RFC do SSE).
class SseDecoder {
  final StringBuffer _residual = StringBuffer();
  String _event = '';
  final List<String> _data = [];
  String? _id;

  List<SseEvent> add(String chunk) {
    final events = <SseEvent>[];
    _residual.write(chunk);
    final text = _residual.toString().replaceAll('\r\n', '\n');
    final lines = text.split('\n');
    // A última "linha" pode estar incompleta: guarda de volta no residual.
    _residual
      ..clear()
      ..write(lines.removeLast());
    for (final line in lines) {
      final event = _consumeLine(line);
      if (event != null) events.add(event);
    }
    return events;
  }

  SseEvent? _consumeLine(String line) {
    if (line.isEmpty) return _dispatch();
    if (line.startsWith(':')) return null; // comentário/heartbeat de linha
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        _event = value;
      case 'data':
        _data.add(value);
      case 'id':
        if (!value.contains('\u0000')) _id = value;
      case 'retry':
        break;
    }
    return null;
  }

  SseEvent? _dispatch() {
    if (_event.isEmpty && _data.isEmpty) return null;
    final event = SseEvent(
      event: _event.isEmpty ? 'message' : _event,
      data: _data.join('\n'),
      id: _id,
    );
    _event = '';
    _data.clear();
    return event;
  }
}

/// Cliente SSE sobre o [ApiClient]: abre `GET /ai/streams/{id}`, decodifica os
/// eventos e reconecta com `Last-Event-ID` quando a conexão cai ou o heartbeat
/// (`ping` a cada 5 s) some, até [maxRetries] tentativas. Encerra em `done`/`error`.
class SseClient {
  SseClient(
    this._api, {
    this.heartbeatTimeout = const Duration(seconds: 20),
    this.retryDelay = const Duration(seconds: 1),
    this.maxRetries = 5,
  });

  final ApiClient _api;
  final Duration heartbeatTimeout;
  final Duration retryDelay;
  final int maxRetries;

  Stream<SseEvent> connect(String path) async* {
    String? lastId;
    var attempt = 0;
    while (true) {
      final body = await _api.openStream(
        path,
        headers: {'Last-Event-ID': ?lastId},
      );
      final decoder = SseDecoder();
      var reconnect = false;
      try {
        final stream = body.stream.timeout(heartbeatTimeout);
        await for (final Uint8List chunk in stream) {
          final text = utf8.decode(chunk, allowMalformed: true);
          for (final event in decoder.add(text)) {
            if (event.id != null) lastId = event.id;
            yield event;
            if (event.isDone || event.isError) return;
          }
        }
        // Stream encerrou sem `done`: tenta reconectar.
        reconnect = true;
      } on TimeoutException {
        reconnect = true;
      }
      if (!reconnect) return;
      attempt++;
      if (attempt > maxRetries) return;
      await Future<void>.delayed(retryDelay);
    }
  }
}
