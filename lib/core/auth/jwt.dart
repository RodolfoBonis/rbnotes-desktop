import 'dart:convert';

/// Decodifica o payload de um JWT (sem validar assinatura — o token vem do
/// endpoint sobre TLS e aqui só lemos `sub`/`name`/`email` para exibir o
/// usuário). Retorna `{}` se o formato for inválido.
Map<String, dynamic> decodeJwtClaims(String jwt) {
  final parts = jwt.split('.');
  if (parts.length < 2) return const {};
  try {
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    switch (payload.length % 4) {
      case 2:
        payload += '==';
      case 3:
        payload += '=';
    }
    final decoded = utf8.decode(base64.decode(payload));
    final json = jsonDecode(decoded);
    return json is Map<String, dynamic> ? json : const {};
  } on Object {
    return const {};
  }
}
