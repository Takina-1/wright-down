import 'package:sync_core/sync_core.dart';
import 'password.dart';
import 'sync_store.dart';

class _User {
  _User(this.userId, this.email, this.hash);
  final String userId;
  final String email;
  final String hash;
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
class FakeSyncStore implements SyncStore {
  final Map<String, _User> _users = {};
  final Map<String, String> _tokens = {}; // token -> userId
  final Map<String, _Entry> _entries = {};
  int _seq = 0;

  @override
  Future<AuthResult> register(String email, String password) async {
    if (_users.containsKey(email)) {
      throw StateError('email already registered');
    }
    final userId = 'u${_seq++}';
    _users[email] = _User(userId, email, hashPassword(password));
    final token = newToken();
    _tokens[token] = userId;
    return AuthResult(userId: userId, token: token);
  }

  @override
  Future<AuthResult?> login(String email, String password) async {
    final u = _users[email];
    if (u == null) {
      // 对不存在的邮箱同样执行一次 bcrypt，使响应耗时与"密码错误"不可区分。
      hashPassword(password);
      return null;
    }
    if (!verifyPassword(password, u.hash)) return null;
    final token = newToken();
    _tokens[token] = u.userId;
    return AuthResult(userId: u.userId, token: token);
  }

  @override
  Future<String?> userIdForToken(String token) async => _tokens[token];

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
      final existing = _entries[p.id];
      final createdAt = existing?.createdAt ?? p.createdAt;
      final merged = <String, FieldValue>{
        ...(existing?.payload ?? const {}),
      };
      for (final f in p.fields.entries) {
        final cur = existing?.payload[f.key] ?? const FieldValue(null, 0);
        merged[f.key] = mergeFieldLww(cur, f.value);
      }
      final seq = ++_seq;
      _entries[p.id] = _Entry(p.id, userId, createdAt, merged, seq);
    }
  }
}
