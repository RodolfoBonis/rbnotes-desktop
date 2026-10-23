import 'dart:async';
import 'dart:io';

/// Resultado do callback de autorização recebido no loopback.
class AuthCallback {
  const AuthCallback({this.code, this.state, this.error});

  final String? code;
  final String? state;
  final String? error;

  bool get isSuccess => code != null && error == null;
}

/// Servidor loopback que fica no ar **só durante o login**: escuta a porta
/// fixa (127.0.0.1:53682) e captura o redirect `/callback?code=&state=` do
/// Keycloak.
///
/// A porta é fixa porque o client público `rbnotes-desktop` registra um
/// redirect URI exato. Tem timeout (5 min por padrão) e fecha assim que recebe
/// o callback.
class LoopbackAuthServer {
  LoopbackAuthServer({
    this.port = 53682,
    this.callbackPath = '/callback',
    this.timeout = const Duration(minutes: 5),
  });

  final int port;
  final String callbackPath;
  final Duration timeout;

  HttpServer? _server;

  /// Sobe o servidor e completa com o primeiro callback recebido (ou lança
  /// `TimeoutException` após [timeout]). Fecha o servidor ao terminar.
  Future<AuthCallback> listen() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    final completer = Completer<AuthCallback>();

    final sub = server.listen((request) async {
      if (request.uri.path != callbackPath) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close().ignore();
        return;
      }
      final params = request.uri.queryParameters;
      final callback = AuthCallback(
        code: params['code'],
        state: params['state'],
        error: params['error'],
      );
      await _respondHtml(request.response, callback);
      if (!completer.isCompleted) completer.complete(callback);
    });

    try {
      return await completer.future.timeout(timeout);
    } finally {
      await sub.cancel();
      await close();
    }
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _respondHtml(HttpResponse response, AuthCallback cb) async {
    final ok = cb.isSuccess;
    final title = ok ? 'Login concluído' : 'Falha no login';
    final body = ok
        ? 'Você já pode voltar ao RbNotes.'
        : 'Não foi possível concluir o login. Volte ao RbNotes.';
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(_page(title, body));
    await response.close();
  }

  static String _page(String title, String body) {
    const style =
        'body{font-family:-apple-system,system-ui,sans-serif;'
        'background:#faf7f2;color:#1d1d1f;display:flex;align-items:center;'
        'justify-content:center;height:100vh;margin:0}'
        '.c{text-align:center;max-width:360px;padding:32px}'
        'h1{font-size:20px;margin:0 0 8px}p{color:#6b6b70;font-size:14px}';
    return <String>[
      '<!doctype html><html lang="pt-BR"><head>',
      '<meta charset="utf-8"><title>', title, '</title>',
      '<style>', style, '</style></head>',
      '<body><div class="c"><h1>', title, '</h1><p>', body, '</p></div>',
      '</body></html>',
    ].join();
  }
}
