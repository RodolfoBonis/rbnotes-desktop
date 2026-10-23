import 'package:rbnotes/core/network/api_client.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';

/// `SyncClient` real: `POST /sync/push` e `GET /sync/pull?since=`.
class ApiSyncClient implements SyncClient {
  ApiSyncClient(this._api);

  final ApiClient _api;

  @override
  Future<PushResult> push(List<SyncChange> changes) async {
    final res = await _api.postJson(
      '/sync/push',
      body: {
        'changes': [for (final c in changes) c.toJson()],
      },
    );
    return PushResult.fromJson(res);
  }

  @override
  Future<PullResult> pull({String? since}) async {
    final res = await _api.getJson(
      '/sync/pull',
      query: {if (since != null && since.isNotEmpty) 'since': since},
    );
    return PullResult.fromJson(res);
  }
}
