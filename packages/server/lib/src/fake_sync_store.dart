import 'dart:convert';

import 'package:sync_core/sync_core.dart';
import 'password.dart';
import 'sync_store.dart';

class _User {
  _User(this.userId, this.email, this.hash);
  final String userId;
  final String email;
  final String hash;
}

class _Token {
  _Token(this.userId, {this.expiresAt});
  final String userId;
  /// access token 过期时间（毫秒）；null = 无过期（兼容 T-06 存量）。
  final int? expiresAt;
}

class _Entry {
  _Entry(this.id, this.userId, this.createdAt, this.payload, this.seq);
  final String id;
  final String userId;
  final int createdAt;
  final Map<String, FieldValue> payload;
  final int seq;
}

/// 内存实现。seq 全局单调，每次 push 递增；pull 返回 seq > cursor 的条目。
///
/// 条目按 (userId, id) 复合键存储，与 deploy/sql/schema.sql 里
/// `entries` 的主键一致：不同用户的日记 id 允许重复，不能互相覆盖。
class FakeSyncStore implements SyncStore {
  final Map<String, _User> _users = {};
  final Map<String, _Token> _tokens = {}; // access token -> _Token
  final Map<String, _Token> _refreshTokens = {}; // refresh token -> _Token
  final Map<(String, String), _Entry> _entries = {};
  int _seq = 0;
  int _userSeq = 0; // 用户 id 单独计数，不占用条目 seq

  @override
  Future<AuthResult> register(String email, String password) async {
    if (_users.containsKey(email)) {
      throw StateError('email already registered');
    }
    final userId = 'u${_userSeq++}';
    _users[email] = _User(userId, email, hashPassword(password));
    final token = newToken();
    final refreshToken = newToken();
    final now = DateTime.now().millisecondsSinceEpoch;
    _tokens[token] = _Token(userId, expiresAt: now + 7 * 24 * 3600 * 1000);
    _refreshTokens[refreshToken] =
        _Token(userId, expiresAt: now + 30 * 24 * 3600 * 1000);
    return AuthResult(
        userId: userId, token: token, refreshToken: refreshToken);
  }

  @override
  Future<AuthResult?> login(String email, String password) async {
    final u = _users[email];
    if (u == null) {
      // 对不存在的邮箱同样执行一次 bcrypt，使响应耗时与“密码错误”不可区分。
      hashPassword(password);  // throws ArgumentError for >72 bytes
      return null;
    }
    if (utf8.encode(password).length > kMaxPasswordBytes) {
      throw ArgumentError('password too long');
    }
    if (!verifyPassword(password, u.hash)) return null;
    final token = newToken();
    final refreshToken = newToken();
    final now = DateTime.now().millisecondsSinceEpoch;
    _tokens[token] = _Token(u.userId, expiresAt: now + 7 * 24 * 3600 * 1000);
    _refreshTokens[refreshToken] =
        _Token(u.userId, expiresAt: now + 30 * 24 * 3600 * 1000);
    return AuthResult(
        userId: u.userId, token: token, refreshToken: refreshToken);
  }

  @override
  Future<String?> userIdForToken(String token) async {
    // T-07：过期 token 视为失效（expiresAt 为 null 兼容存量）。
    final t = _tokens[token];
    if (t == null) return null;
    if (t.expiresAt != null && t.expiresAt! <= DateTime.now().millisecondsSinceEpoch) {
      return null;
    }
    return t.userId;
  }

  @override
  Future<AuthResult> refresh(String refreshToken) async {
    final t = _refreshTokens[refreshToken];
    if (t == null ||
        (t.expiresAt != null &&
            t.expiresAt! <= DateTime.now().millisecondsSinceEpoch)) {
      throw StateError('invalid refresh token');
    }
    // 轮换：旧 refresh 作废，签发新 access + 新 refresh。
    _refreshTokens.remove(refreshToken);
    final newRefresh = newToken();
    final newAccess = newToken();
    final now = DateTime.now().millisecondsSinceEpoch;
    _refreshTokens[newRefresh] =
        _Token(t.userId, expiresAt: now + 30 * 24 * 3600 * 1000);
    _tokens[newAccess] = _Token(t.userId, expiresAt: now + 7 * 24 * 3600 * 1000);
    return AuthResult(userId: t.userId, token: newAccess, refreshToken: newRefresh);
  }

  @override
  Future<SyncPullResponse> pull(String userId, int cursor) async {
    final matched = _entries.values
        .where((e) => e.userId == userId && e.seq > cursor)
        .toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    final newCursor = matched.isEmpty
        ? cursor
        : matched.map((e) => e.seq).reduce((a, b) => a > b ? a : b);
    return SyncPullResponse(
      cursor: newCursor,
      entries: matched
          .map((e) => SyncEntry(
                id: e.id,
                createdAt: e.createdAt,
                fields: Map<String, FieldValue>.of(e.payload),
              ))
          .toList(),
    );
  }

  @override
  Future<void> push(String userId, SyncPushBatch batch) async {
    for (final p in batch.patches) {
      final key = (userId, p.id);
      final existing = _entries[key];
      final createdAt = existing?.createdAt ?? p.createdAt;
      final merged = <String, FieldValue>{
        ...(existing?.payload ?? const {}),
      };
      for (final f in p.fields.entries) {
        final cur = existing?.payload[f.key] ?? const FieldValue(null, 0);
        merged[f.key] = mergeFieldLww(cur, f.value);
      }
      final seq = ++_seq;
      _entries[key] = _Entry(p.id, userId, createdAt, merged, seq);
    }
  }
}
