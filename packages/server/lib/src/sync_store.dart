import 'package:sync_core/sync_core.dart';

/// 服务端存储与逻辑抽象。FakeSyncStore（内存，本 Part）实现；
/// PostgresSyncStore（真实 SQL）延后到 postgres 环境就绪。
abstract interface class SyncStore {
  Future<AuthResult> register(String email, String password);
  Future<AuthResult?> login(String email, String password);
  Future<String?> userIdForToken(String token);
  /// T-07：refresh token 换新 access token（轮换 refresh）。
  Future<AuthResult> refresh(String refreshToken);

  Future<SyncPullResponse> pull(String userId, int cursor);
  Future<void> push(String userId, SyncPushBatch batch);
}
