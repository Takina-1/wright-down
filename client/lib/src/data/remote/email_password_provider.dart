import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_core/sync_core.dart';

import 'remote_repo.dart';

/// T-07/T-08：登录态会话（access + refresh token + 过期时间）。
/// 经 [TokenStore] 持久化——SharedPreferences 真机持久化，InMemory 开发/测试。
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;

  /// access token 过期时间（客户端估算：now + 7 天）。仅存储用——
  /// 过期判定由服务端 401 驱动（RemoteRepo 的 refresh 重试）。
  final DateTime expiresAt;
}

/// token 持久化抽象：由调用方实现（SharedPreferences 真机 / InMemory 开发）。
abstract interface class TokenStore {
  Future<AuthSession?> read();

  Future<void> write(AuthSession? session);
}

/// 内存 token 存储：进程内保存登录态（开发/测试用）。
class InMemoryTokenStore implements TokenStore {
  AuthSession? _session;
  @override
  Future<AuthSession?> read() async => _session;
  @override
  Future<void> write(AuthSession? session) async {
    _session = session;
  }
}

/// SharedPreferences 持久化（T-08）：JSON 序列化 AuthSession。
/// App 重启后登录态保留——免重新登录。
class SharedPreferencesTokenStore implements TokenStore {
  SharedPreferencesTokenStore(this._prefs);

  final SharedPreferences _prefs;
  static const String _kKey = 'auth_session';

  @override
  Future<AuthSession?> read() async {
    final raw = _prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return AuthSession(
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String,
        expiresAt:
            DateTime.fromMillisecondsSinceEpoch(j['expiresAt'] as int),
      );
    } on Object {
      // 脏数据不崩溃——退回未登录（与 tags/stamps 解码口径一致）。
      return null;
    }
  }

  @override
  Future<void> write(AuthSession? session) async {
    if (session == null) {
      await _prefs.remove(_kKey);
      return;
    }
    await _prefs.setString(_kKey, jsonEncode({
      'accessToken': session.accessToken,
      'refreshToken': session.refreshToken,
      'expiresAt': session.expiresAt.millisecondsSinceEpoch,
    }));
  }
}

/// 邮箱密码鉴权：基于 [RemoteRepo] 实现 [AuthProvider]，
/// token 经 [TokenStore] 持久化（T-08）。
class EmailPasswordProvider implements AuthProvider {
  EmailPasswordProvider(this.client, this.baseUrl, this.tokenStore,
      {this.handler});

  final http.Client client;
  final String baseUrl;
  final TokenStore tokenStore;
  final HttpHandler? handler;

  RemoteRepo get _repo =>
      RemoteRepo(client, baseUrl, const SyncCodec(), handler: handler);

  @override
  Future<AuthResult> register(String email, String password) async {
    final r = await _repo.register(email, password);
    await tokenStore.write(_session(r));
    return r;
  }

  @override
  Future<AuthResult> login(String email, String password) async {
    final r = await _repo.login(email, password);
    if (r == null) throw StateError('invalid email or password');
    await tokenStore.write(_session(r));
    return r;
  }

  @override
  Future<AuthResult?> current() async {
    final s = await tokenStore.read();
    if (s == null) return null;
    return AuthResult(userId: 'cached', token: s.accessToken);
  }

  @override
  Future<void> signOut() async => tokenStore.write(null);

  /// T-07：refresh token 换新 access token（经 /auth/refresh 端点，
  /// 服务端轮换 refresh）。成功后存新 AuthSession。
  Future<AuthResult> refresh() async {
    final s = await tokenStore.read();
    if (s == null) throw StateError('not logged in');
    final r = await _repo.refresh(s.refreshToken);
    await tokenStore.write(_session(r));
    return r;
  }

  AuthSession _session(AuthResult r) => AuthSession(
        accessToken: r.token,
        refreshToken: r.refreshToken ?? '',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
}
