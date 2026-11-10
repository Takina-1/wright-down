import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:postgres/postgres.dart';
import 'package:sync_core/sync_core.dart';
import 'password.dart';
import 'pg_config.dart';
import 'sync_store.dart';

/// PostgreSQL 实现。语义基准 = FakeSyncStore，逐条对齐：
/// - register：邮箱已存在 → StateError（handler → 409，且不执行 bcrypt）；
///   新邮箱 → bcrypt 哈希（超长抛 ArgumentError → handler 400）。
/// - login：邮箱不存在 → 也跑一次 bcrypt（防时序）；校验失败返回 null（401）。
/// - pull：seq > cursor 升序返回；空批 cursor 不变；非空推进到本批最大 seq。
/// - push：一个事务；逐 patch 经 sync_seq 行锁取号；字段级 LWW（FieldValue.t
///   毫秒戳）；同 (user_id, id) 覆盖 payload 与 seq；created_at 首次写入后冻结。
///
/// AC-07：seq 分配与条目写入同事务，行锁持有至提交，seq 顺序 == 提交顺序。
/// 演示环境单连接：Dart 单线程 + 本存储串行化满足并发正确性（并发证据见
/// 集成测试；后续若出现吞吐上限再升级 ConnectionPool）。
///
/// SQL 中 `$n` 是 PostgreSQL 占位符——Dart 字符串用 `\$` 转义输出字面 `$`。
class PostgresSyncStore implements SyncStore {
  PostgresSyncStore(this._conn);

  final Connection _conn;

  /// 供 main 装配：按 [PgConfig] 打开连接。
  static Future<PostgresSyncStore> connect(PgConfig config) async =>
      PostgresSyncStore(
        await Connection.open(
          Endpoint(
            host: config.host,
            port: config.port,
            database: config.db,
            username: config.user,
            password: config.password,
          ),
          settings: ConnectionSettings(
            connectTimeout: config.timeout,
            // ECS 本地 PG 未启用 SSL——postgres 包 3.6 默认要求 SSL，
            // 本地回环连接必须显式禁用（未来上云 RDS 时再按需开启）。
            sslMode: SslMode.disable,
          ),
        ),
      );

  Future<void> close() => _conn.close();

  @override
  Future<AuthResult> register(String email, String password) async {
    // 与 FakeSyncStore 同序：邮箱已存在 → StateError，且不执行 bcrypt。
    final existed = await _conn.execute(
      'SELECT 1 FROM users WHERE email = \$1',
      parameters: [email],
    );
    if (existed.isNotEmpty) {
      throw StateError('email already registered');
    }
    // 新邮箱 → bcrypt 哈希（超长由 bcrypt 库抛 ArgumentError → handler 400）。
    final hash = hashPassword(password);
    final userId = _userId();
    final token = newToken();
    final refreshToken = newToken();
    await _conn.execute(
      'INSERT INTO users (id, email, password_hash) VALUES (\$1, \$2, \$3)',
      parameters: [userId, email, hash],
    );
    await _conn.execute(
      'INSERT INTO tokens (token, user_id, expires_at) '
      "VALUES (\$1, \$2, now() + interval '7 days')",
      parameters: [token, userId],
    );
    await _conn.execute(
      'INSERT INTO refresh_tokens (token, user_id, expires_at) '
      "VALUES (\$1, \$2, now() + interval '30 days')",
      parameters: [refreshToken, userId],
    );
    return AuthResult(userId: userId, token: token, refreshToken: refreshToken);
  }

  @override
  Future<AuthResult?> login(String email, String password) async {
    final row = await _conn.execute(
      'SELECT id, password_hash FROM users WHERE email = \$1',
      parameters: [email],
    ).then((r) => r.isEmpty ? null : r.first);

    if (row == null) {
      // 对不存在的邮箱同样执行一次 bcrypt，使响应耗时与“密码错误”不可区分。
      hashPassword(password);
      return null;
    }
    // 显式长度检查：存在邮箱 + 超长 → ArgumentError（与 FakeSyncStore 一致）。
    if (utf8.encode(password).length > kMaxPasswordBytes) {
      throw ArgumentError('password too long');
    }
    if (!verifyPassword(password, row[1] as String)) {
      return null;
    }
    final token = newToken();
    final refreshToken = newToken();
    await _conn.execute(
      'INSERT INTO tokens (token, user_id, expires_at) '
      "VALUES (\$1, \$2, now() + interval '7 days')",
      parameters: [token, row[0] as String],
    );
    await _conn.execute(
      'INSERT INTO refresh_tokens (token, user_id, expires_at) '
      "VALUES (\$1, \$2, now() + interval '30 days')",
      parameters: [refreshToken, row[0] as String],
    );
    return AuthResult(
        userId: row[0] as String, token: token, refreshToken: refreshToken);
  }

  @override
  Future<String?> userIdForToken(String token) async {
    // T-07：access token 过期（expires_at <= now()）视为失效 → null（401）。
    // expires_at IS NULL 兼容存量 token（无过期）。
    final result = await _conn.execute(
      'SELECT user_id FROM tokens '
      'WHERE token = \$1 AND (expires_at IS NULL OR expires_at > now())',
      parameters: [token],
    );
    return result.isEmpty ? null : result.first[0] as String;
  }

  /// T-07：refresh token 换新 access token（轮换 refresh）。
  /// refresh token 过期/不存在 → StateError（handler 401）；
  /// 有效 → 事务内 DELETE 旧 refresh + INSERT 新 refresh（30 天）+ 新 access（7 天）。
  Future<AuthResult> refresh(String refreshToken) async {
    final row = await _conn.execute(
      'SELECT user_id FROM refresh_tokens '
      'WHERE token = \$1 AND expires_at > now()',
      parameters: [refreshToken],
    );
    if (row.isEmpty) {
      throw StateError('invalid refresh token');
    }
    final userId = row.first[0] as String;
    return _conn.runTx<AuthResult>((tx) async {
      // 轮换：旧 refresh token 作废（防重放）。
      await tx.execute(
        'DELETE FROM refresh_tokens WHERE token = \$1',
        parameters: [refreshToken],
      );
      final newRefresh = newToken();
      final newAccess = newToken();
      await tx.execute(
        'INSERT INTO refresh_tokens (token, user_id, expires_at) '
        "VALUES (\$1, \$2, now() + interval '30 days')",
        parameters: [newRefresh, userId],
      );
      await tx.execute(
        'INSERT INTO tokens (token, user_id, expires_at) '
        "VALUES (\$1, \$2, now() + interval '7 days')",
        parameters: [newAccess, userId],
      );
      return AuthResult(
          userId: userId, token: newAccess, refreshToken: newRefresh);
    });
  }

  @override
  Future<SyncPullResponse> pull(String userId, int cursor) async {
    final result = await _conn.execute(
      '''SELECT id, round(EXTRACT(EPOCH FROM created_at) * 1000)::bigint,
              payload::text, seq
         FROM entries
        WHERE user_id = \$1 AND seq > \$2
        ORDER BY seq''',
      parameters: [userId, cursor],
    );
    if (result.isEmpty) {
      return SyncPullResponse(cursor: cursor, entries: []);
    }
    var newCursor = cursor;
    final entries = <SyncEntry>[];
    for (final row in result) {
      final seq = _toInt(row[3]);
      if (seq > newCursor) newCursor = seq;
      entries.add(SyncEntry(
        id: row[0] as String,
        createdAt: _toInt(row[1]),
        fields: _decodePayload(row[2] as String),
      ));
    }
    return SyncPullResponse(cursor: newCursor, entries: entries);
  }

  @override
  Future<void> push(String userId, SyncPushBatch batch) async {
    if (batch.patches.isEmpty) return;
    await _conn.runTx((tx) async {
      for (final patch in batch.patches) {
        // AC-07：行锁取号，锁持有至事务提交——并发 push 串行化。
        final seqRes = await tx.execute(
          '''UPDATE sync_seq SET value = value + 1
              WHERE id = 1
              RETURNING value''',
          parameters: [],
        );
        final seq = _toInt(seqRes.first.first);

        final oldRes = await tx.execute(
          '''SELECT created_at, payload::text
             FROM entries
            WHERE user_id = \$1 AND id = \$2''',
          parameters: [userId, patch.id],
        );

        final merged = <String, FieldValue>{};
        if (oldRes.isEmpty) {
          for (final e in patch.fields.entries) {
            merged[e.key] = e.value;
          }
        } else {
          for (final e in _decodePayload(oldRes.first[1] as String).entries) {
            merged[e.key] = e.value;
          }
          for (final e in patch.fields.entries) {
            merged[e.key] = mergeFieldLww(
              merged[e.key] ?? const FieldValue(null, 0),
              e.value,
            );
          }
        }

        // 首次写入 created_at = 快照毫秒；后续只更新 payload 与 seq。
        final createdMillis =
            oldRes.isEmpty ? patch.createdAt : _createdMillis(oldRes.first[0]);
        await tx.execute(
          '''INSERT INTO entries (user_id, id, payload, created_at, seq)
             VALUES (\$1, \$2, \$3::jsonb, to_timestamp(\$4::bigint / 1000.0), \$5)
             ON CONFLICT (user_id, id)
             DO UPDATE SET payload = \$3::jsonb, seq = \$5''',
          parameters: [
            userId,
            patch.id,
            _encodePayload(merged),
            createdMillis,
            seq,
          ],
        );
      }
    });
  }

  static int _createdMillis(Object? v) {
    if (v is DateTime) {
      return v.millisecondsSinceEpoch;
    }
    if (v is BigInt) return v.toInt();
    return (v as num).toInt();
  }

  static int _toInt(Object? v) {
    if (v == null) return 0;
    if (v is BigInt) return v.toInt();
    return (v as num).toInt();
  }

  /// 与 sync_core `SyncCodec` 编码逐字段一致：{"field": {"v":…, "t":…}}。
  static String _encodePayload(Map<String, FieldValue> fields) {
    final encoded = <String, Object?>{};
    for (final e in fields.entries) {
      encoded[e.key] = {'v': e.value.v, 't': e.value.t};
    }
    return jsonEncode(encoded);
  }

  /// payload::text 读回后解码为 Map<String, FieldValue>。
  static Map<String, FieldValue> _decodePayload(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final fields = <String, FieldValue>{};
    for (final e in decoded.entries) {
      final v = e.value as Map<String, dynamic>;
      fields[e.key] = FieldValue(v['v'], (v['t'] as num).toInt());
    }
    return fields;
  }

  /// 跨实例唯一：毫秒 + 4 位随机 hex（毫秒内多实例也不冲突）。
  static String _userId() {
    final rng = Random.secure();
    final rand = Uint8List(4);
    for (var i = 0; i < rand.length; i++) {
      rand[i] = rng.nextInt(256);
    }
    final hex = rand
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'u${DateTime.now().millisecondsSinceEpoch}$hex';
  }
}
