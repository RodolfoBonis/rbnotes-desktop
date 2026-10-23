import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/ai/data/sse_client.dart';

void main() {
  group('SseDecoder', () {
    test('decodifica event/data/id simples', () {
      final d = SseDecoder();
      final events = d.add('event: json\ndata: {"text":"oi"}\nid: 7\n\n');
      expect(events, hasLength(1));
      expect(events.first.event, 'json');
      expect(events.first.data, '{"text":"oi"}');
      expect(events.first.id, '7');
    });

    test(r'junta várias linhas data com \n', () {
      final d = SseDecoder();
      final events = d.add('data: a\ndata: b\n\n');
      expect(events.single.data, 'a\nb');
      expect(events.single.event, 'message');
    });

    test('reagrupa linha partida entre chunks', () {
      final d = SseDecoder();
      expect(d.add('event: jso'), isEmpty);
      final events = d.add('n\ndata: {"x":1}\n\n');
      expect(events, hasLength(1));
      expect(events.first.event, 'json');
      expect(events.first.data, '{"x":1}');
    });

    test(r'ignora comentários (heartbeat) e trata \r\n', () {
      final d = SseDecoder();
      final events = d.add(': ping\r\nevent: ping\r\ndata: \r\n\r\n');
      expect(events, hasLength(1));
      expect(events.first.event, 'ping');
    });

    test('múltiplos eventos num só chunk', () {
      final d = SseDecoder();
      final events = d.add(
        'event: status\ndata: queued\n\nevent: done\ndata: {}\n\n',
      );
      expect(events.map((e) => e.event), ['status', 'done']);
      expect(events.last.isDone, isTrue);
    });
  });
}
