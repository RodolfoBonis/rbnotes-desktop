import 'dart:async';
import 'dart:io';

/// Servidor HTTP loopback para os testes de rede (sem Docker nem backend).
class LocalServer {
  LocalServer(this._server);

  final HttpServer _server;

  static Future<LocalServer> start(
    FutureOr<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        await handler(request);
      } on Object {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } on Object {
          // resposta já fechada
        }
      }
    });
    return LocalServer(server);
  }

  int get port => _server.port;
  String get base => 'http://127.0.0.1:$port';

  Future<void> close() => _server.close(force: true);
}
