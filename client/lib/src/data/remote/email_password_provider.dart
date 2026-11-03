import 'package:http/http.dart' as http;
import 'package:sync_core/sync_core.dart';

import 'remote_repo.dart';

/// token 持久化抽象：由调用方实现（如本地安全存储）。
abstract interface class TokenStore {
  Future<String?> read();

  Future<void> write(String? token);
}

/// 邮箱密码鉴权：基于 [RemoteRepo] 实现 [AuthProvider]，token 经 [TokenStore] 持久化。
class EmailPasswordProvider implements AuthProvider {
  EmailPasswordProvider(this.client, this.baseUrl, this.tokenStore, {this.handler});

  final http.Client client;
  final String baseUrl;
  final TokenStore tokenStore;
  final HttpHandler? handler;

  RemoteRepo get _repo =>
      RemoteRepo(client, baseUrl, const SyncCodec(), handler: handler);

  @override
  Future<AuthResult> register(String email, String password) async {
    final r = await _repo.register(email, password);
    await tokenStore.write(r.token);
    return r;
  }

  @override
  Future<AuthResult> login(String email, String password) async {
    final r = await _repo.login(email, password);
    if (r == null) throw StateError('invalid email or password');
    await tokenStore.write(r.token);
    return r;
  }

  @override
  Future<AuthResult?> current() async {
    final t = await tokenStore.read();
    if (t == null) return null;
    return AuthResult(userId: 'cached', token: t);
  }

  @override
  Future<void> signOut() async => tokenStore.write(null);
}
