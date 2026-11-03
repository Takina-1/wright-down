import 'package:sync_core/sync_core.dart';

/// 服务端存储与逻辑抽象。FakeSyncStore（内存，本 Part）实现；
/// PostgresSyncStore（真实 SQL）延后到 postgres 环境就绪。
abstract interface class SyncStore {
  Future<AuthResult> register(String email, String password);
  Future<AuthResult?> login(String email, String password);
  Future<String?> userIdForToken(String token);

  Future<SyncPullResponse> pull(String userId, int cursor);
  Future<void> push(String userId, SyncPushBatch batch);
}
