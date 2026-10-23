import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:rbnotes/core/auth/auth_tokens.dart';
import 'package:rbnotes/core/auth/oidc_client.dart';
import 'package:rbnotes/core/auth/token_store.dart';
import 'package:rbnotes/core/network/api_client.dart';
import 'package:rbnotes/core/network/api_error.dart';
import 'package:rbnotes/core/network/session_events.dart';
import 'package:rbnotes/features/sync/data/audio_sync.dart';

/// `ApiClient` descartável para os fakes: nunca é tocado porque os métodos de
/// rede são sobrescritos, mas o `AudioSync` exige um no construtor.
ApiClient dummyApi() => ApiClient(
  baseUrl: 'http://127.0.0.1:1/v1',
  tokens: MemoryTokenStore(
    const AuthTokens(accessToken: 'a', refreshToken: 'r'),
  ),
  oidc: OidcClient(
    dio: Dio(),
    issuer: 'http://127.0.0.1:1/realms/x',
    clientId: 'c',
    redirectUri: 'http://127.0.0.1:53682/callback',
  ),
  events: SessionEvents(),
);

/// `AudioSync` de teste: registra uploads e pode simular falha ou um download
/// (grava bytes e reporta progresso), sem rede.
class FakeAudioSync extends AudioSync {
  FakeAudioSync() : super(dummyApi());

  final List<String> uploaded = [];
  bool failUploads = false;

  /// Bytes entregues por [downloadToFile]; null simula `404` (indisponível).
  Uint8List? downloadBody;

  @override
  Future<void> uploadFile(
    String noteId,
    String filePath, {
    int startPart = 1,
    String contentType = 'audio/mp4',
  }) async {
    if (failUploads) throw const ApiError.network();
    uploaded.add(noteId);
  }

  @override
  Future<int> downloadToFile(
    String noteId,
    String destPath, {
    int chunk = AudioSync.chunkSize,
    void Function(int received, int? total)? onProgress,
  }) async {
    final body = downloadBody;
    if (body == null) throw const ApiError(statusCode: 404);
    onProgress?.call(body.length ~/ 2, body.length);
    await File(destPath).writeAsBytes(body);
    onProgress?.call(body.length, body.length);
    return body.length;
  }
}
