import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sync_core/sync_core.dart';

import '../sync/sync_engine.dart';

/// 可选的 HTTP 处理替身，测试注入以避开真实网络。
typedef HttpHandler = Future<http.Response> Function(http.Request request);

/// 远程同步仓库：封装 sync_core 协议的 HTTP 往返（pull/push/register/login/refresh）。
/// 通过注入 [http.Client] + baseUrl + [SyncCodec] 工作；测试可注入 [handler] 替身。
///
/// 实现 [SyncRemote]：pull/push 签名与接口一致，使 SyncEngine 可注入本类或测试替身。
///
/// T-07（AC-08）：pull/push 收到 401 → 调用 [tokenRefresher] 换新 access token
/// → 重试一次 → 仍 401 → 抛 StateError（上层 SyncEngine 置 failed 提示重登录）。
class RemoteRepo implements SyncRemote {
  RemoteRepo(this.client, this.baseUrl, this.codec,
      {this.handler, this.tokenRefresher});

  final http.Client client;
  final String baseUrl;
  final SyncCodec codec;
  final HttpHandler? handler;

  /// 401 时调用——返回新 access token。注入 EmailPasswordProvider.refresh。
  final Future<String> Function()? tokenRefresher;

  Future<http.Response> _send(http.Request req) async {
    final h = handler;
    if (h != null) return h(req);
    final sr = await client.send(req);
    return http.Response.fromStream(sr);
  }

  /// 发送请求；401 时用 [tokenRefresher] 换新 token 重试一次。
  Future<http.Response> _sendWithRetry(http.Request req) async {
    final r = await _send(req);
    if (r.statusCode != 401) return r;
    final refresher = tokenRefresher;
    if (refresher == null) return r; // 无 refresher——原样返回（上层处理）
    final newToken = await refresher();
    final req2 = http.Request(req.method, req.url);
    req2.headers.addAll(req.headers);
    req2.headers['authorization'] = 'Bearer $newToken';
    req2.body = req.body;
    final r2 = await _send(req2);
    if (r2.statusCode == 401) {
      throw StateError('token refresh failed');
    }
    return r2;
  }

  /// 拉取自 [cursor] 之后的变更；返回服务端游标与条目列表。
  @override
  Future<SyncPullResponse> pull(String token, int cursor) async {
    final req = http.Request('GET', Uri.parse('$baseUrl/sync?cursor=$cursor'));
    req.headers['authorization'] = 'Bearer $token';
    final r = await _sendWithRetry(req);
    return codec.decodePull(utf8.decode(r.bodyBytes));
  }

  /// 推送变更批次。
  @override
  Future<void> push(String token, SyncPushBatch batch) async {
    final req = http.Request('POST', Uri.parse('$baseUrl/sync/batch'));
    req.headers['authorization'] = 'Bearer $token';
    req.headers['content-type'] = 'application/json';
    req.body = codec.encodePush(batch);
    await _sendWithRetry(req);
  }

  /// 邮箱注册，返回鉴权结果（token 由调用方持久化）。
  Future<AuthResult> register(String email, String password) async {
    final req = http.Request('POST', Uri.parse('$baseUrl/auth/register'));
    req.headers['content-type'] = 'application/json';
    req.body = jsonEncode({'email': email, 'password': password});
    final r = await _send(req);
    return _authResult(r);
  }

  /// 邮箱登录；401 表示凭证无效，返回 null。
  Future<AuthResult?> login(String email, String password) async {
    final req = http.Request('POST', Uri.parse('$baseUrl/auth/login'));
    req.headers['content-type'] = 'application/json';
    req.body = jsonEncode({'email': email, 'password': password});
    final r = await _send(req);
    if (r.statusCode == 401) return null;
    return _authResult(r);
  }

  /// T-07：refresh token 换新 access token（POST /auth/refresh）。
  Future<AuthResult> refresh(String refreshToken) async {
    final req = http.Request('POST', Uri.parse('$baseUrl/auth/refresh'));
    req.headers['content-type'] = 'application/json';
    req.body = jsonEncode({'refreshToken': refreshToken});
    final r = await _send(req);
    if (r.statusCode == 401) throw StateError('invalid refresh token');
    return _authResult(r);
  }

  AuthResult _authResult(http.Response r) {
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return AuthResult(
      userId: j['userId'] as String,
      token: j['token'] as String,
      refreshToken: j['refreshToken'] as String?,
    );
  }
}
