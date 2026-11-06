# F013 云同步实现计划 · Part 3：客户端同步引擎（核心）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 客户端同步引擎核心：schema v6 字段级时间戳、Entry↔SyncEntry 映射、RemoteRepo（HTTP）、SyncEngine（脏队列/推拉循环/退避）。UI（鉴权/认领/同步状态）另见 Part 3b。

**Architecture:** SyncEngine 是 LocalRepo 的异步旁路——LocalRepo 仍是唯一真相源，写入永不失败。字段级 LWW 需要 per-field 时间戳（sync_stamps），否则离线冲突会用旧值覆盖新值。SyncEngine 推拉都用 sync_core 的 mergeFieldLww，与服务端一致。

**Tech Stack:** Dart/Flutter 3.13.7，`http`（RemoteRepo），`sqflite_common_ffi`（宿主测试），sync_core（path 依赖）。

## 全局约束

- SDK：`sdk: ^3.13.7`。
- schema：entries 表加 `sync_stamps TEXT`（JSON map field→millis），version 升 6，迁移幂等。
- 同步字段：content / mood / tags / deletedAt（photo 延后到 Part 4）。
- 字段级 LWW：每字段独立时间戳，取大；平局取推送方（与 sync_core 一致）。
- 架构铁律：UI 不碰 RemoteRepo；写入只走 LocalRepo；Domain 不依赖框架/SDK。
- 提交信息：`<type>:<中文说明>,<english summary>`，标注 `feat(F013)`。

## 文件结构

```
client/lib/src/domain/sync/
  entry_sync_map.dart        # Entry↔SyncEntry 映射（纯函数）
client/lib/src/data/remote/
  remote_repo.dart           # RemoteRepo（HTTP，用 sync_core 协议）
  email_password_provider.dart # EmailPasswordProvider + TokenStore
client/lib/src/data/sync/
  sync_engine.dart           # SyncEngine（脏队列/推拉/退避/触发）
client/test/domain/sync/
  entry_sync_map_test.dart
client/test/data/remote/
  remote_repo_test.dart      # fake http
  email_password_provider_test.dart
client/test/data/sync/
  sync_engine_test.dart      # fake RemoteRepo + sqflite_common_ffi
```

> 修改既有：`client/lib/src/domain/entry.dart`（加 syncStamps）、`client/lib/src/data/local/sqlite_entry_repository.dart`（v6 迁移 + 时间戳维护）。

---

## Task 1: schema v6 sync_stamps + Entry 模型 + 仓储时间戳维护

**Files:**
- Modify: `client/lib/src/domain/entry.dart`（加 syncStamps）
- Modify: `client/lib/src/data/local/sqlite_entry_repository.dart`（v6 迁移 + save/softDelete/restore 维护 sync_stamps）
- Test: `client/test/data/sqlite_sync_stamps_test.dart`

**Interfaces:**
- Consumes: `Entry`（扩展）。
- Produces: `Entry.syncStamps`（`Map<String,int>`，字段→毫秒）；仓储 save 对变更字段打 now、softDelete/restore 打 deletedAt=now。

- [ ] **Step 1: 写失败测试**

`client/test/data/sqlite_sync_stamps_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

Future<SqliteEntryRepository> _open() async {
  final ffi = sqfliteDatabaseFactory();
  return SqliteEntryRepository(factory: ffi, path: ':memory:');
}

void main() {
  group('sync_stamps 维护', () {
    test('新建条目所有字段打 now 时间戳', () async {
      final repo = await _open();
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await repo.save(Entry(
        id: 'e1', content: 'hi', createdAt: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
        dayKey: '2026-11-03', mood: 'happy', tags: ['a'],
      ));
      final all = await repo.exportAll();
      final stamps = all.single.syncStamps;
      expect(stamps['content'], greaterThanOrEqualTo(now));
      expect(stamps['mood'], greaterThanOrEqualTo(now));
      expect(stamps['tags'], greaterThanOrEqualTo(now));
      await repo.close();
    });

    test('只改字段时只打该字段时间戳', () async {
      final repo = await _open();
      final t1 = DateTime.now().toUtc().millisecondsSinceEpoch;
      await repo.save(Entry(
        id: 'e1', content: 'old', createdAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
        dayKey: '2026-11-03', mood: 'happy', tags: ['a'],
      ));
      // 改正文，心情/标签不变
      final t2 = t1 + 1000;
      await repo.save(Entry(
        id: 'e1', content: 'new', createdAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(t2, isUtc: true),
        dayKey: '2026-11-03', mood: 'happy', tags: ['a'],
      ));
      final all = await repo.exportAll();
      final stamps = all.single.syncStamps;
      expect(stamps['content'], greaterThanOrEqualTo(t2)); // 正文变了，更新
      expect(stamps['mood'], lessThan(t2)); // 心情没变，保留旧戳
      await repo.close();
    });

    test('软删除打 deletedAt 时间戳', () async {
      final repo = await _open();
      final t1 = DateTime.now().toUtc().millisecondsSinceEpoch;
      await repo.save(Entry(
        id: 'e1', content: 'x', createdAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
        dayKey: '2026-11-03',
      ));
      await repo.softDelete('e1');
      final all = await repo.exportAll();
      expect(all.single.syncStamps['deletedAt'], greaterThan(0));
      await repo.close();
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && ..\scripts\flutter.ps1 test test/data/sqlite_sync_stamps_test.dart`
Expected: FAIL —— `syncStamps` 字段不存在。

- [ ] **Step 3: 写实现**

Modify `client/lib/src/domain/entry.dart`，Entry 加 `syncStamps`：

```dart
class Entry {
  const Entry({
    required this.id, required this.content, required this.createdAt,
    required this.updatedAt, required this.dayKey,
    this.deletedAt, this.mood, this.tags = const [], this.photo,
    this.syncStamps = const {},   // 字段级同步时间戳（毫秒），sync 字段名→时间
  });
  // ... 既有字段 ...
  final Map<String, int> syncStamps; // 新增
}
```

Modify `client/lib/src/data/local/sqlite_entry_repository.dart`：

1. schema version 5 → 6；onUpgrade 加 v6 迁移（幂等加 sync_stamps 列）：
```dart
options: OpenDatabaseOptions(version: 6, ...)
// onUpgrade 末尾加：
if (oldVersion < 6) {
  final columns = await db.rawQuery('PRAGMA table_info(entries)');
  final has = columns.any((r) => r['name'] == 'sync_stamps');
  if (!has) await db.execute('ALTER TABLE entries ADD COLUMN sync_stamps TEXT');
}
// onCreate 的 CREATE TABLE 加：sync_stamps TEXT
```

2. save 改为读当前值→比较→打戳。把 `save` 里的 upsert 改为：先 query 当前行，算新 syncStamps，再 update/insert。关键片段：
```dart
Future<void> save(Entry entry) async {
  if (entry.id.isEmpty || entry.content.trim().isEmpty) throw ArgumentError(...);
  final db = await _database();
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  final rows = await db.query('entries', where: 'id = ?', whereArgs: [entry.id], limit: 1);
  final existing = rows.isEmpty ? null : _toEntry(rows.first);
  final newStamps = _computeStamps(existing, entry, now);
  final stampsJson = jsonEncode(newStamps);
  await db.transaction((txn) async {
    final updated = await txn.update('entries', {
      'content': entry.content, 'updated_at': entry.updatedAt.millisecondsSinceEpoch,
      if (entry.deletedAt != null) 'deleted_at': entry.deletedAt.millisecondsSinceEpoch,
      'mood': entry.mood, 'tags': jsonEncode(entry.tags), 'photo': entry.photo,
      'sync_stamps': stampsJson,
    }, where: 'id = ?', whereArgs: [entry.id]);
    if (updated == 0) {
      await txn.insert('entries', {
        'id': entry.id, 'content': entry.content,
        'created_at': entry.createdAt.millisecondsSinceEpoch,
        'updated_at': entry.updatedAt.millisecondsSinceEpoch,
        'day_key': entry.dayKey,
        if (entry.deletedAt != null) 'deleted_at': entry.deletedAt.millisecondsSinceEpoch,
        'mood': entry.mood, 'tags': jsonEncode(entry.tags), 'photo': entry.photo,
        'sync_stamps': stampsJson,
      });
    }
  });
}

Map<String, int> _computeStamps(Entry? existing, Entry e, int now) {
  final old = existing?.syncStamps ?? const {};
  final stamps = <String, int>{...old};
  void bump(String field, Object? newV, Object? oldV) {
    if (newV != oldV) stamps[field] = now;
  }
  bump('content', e.content, existing?.content);
  bump('mood', e.mood, existing?.mood);
  bump('tags', e.tags, existing?.tags);
  // deletedAt 由 softDelete/restore 维护，save 不碰
  return stamps;
}
```

3. softDelete/restore 里把 `deleted_at` 写入时同步打 `sync_stamps['deletedAt']=now`（解析旧 stamps JSON 改 deletedAt 再写回）：
```dart
// softDelete 的 txn.update 改为：
final cur = await txn.query('entries', columns: ['sync_stamps'], where: 'id = ?', whereArgs: [id], limit: 1);
final stamps = _decodeStamps(cur.first?['sync_stamps']);
stamps['deletedAt'] = now;
await txn.update('entries', {'deleted_at': now, 'updated_at': stamp, 'sync_stamps': jsonEncode(stamps)}, where: 'id = ?', whereArgs: [id]);
// restore 同理：stamps['deletedAt'] = now，deleted_at 写 null
```

4. `_toEntry` 解析 sync_stamps：
```dart
final stamps = <String, int>{};
final raw = row['sync_stamps'];
if (raw is String && raw.isNotEmpty) {
  try {
    final d = jsonDecode(raw);
    if (d is Map) for (final e in d.entries) if (e.value is int) stamps[e.key as String] = e.value as int;
  } catch (_) {}
}
// Entry(... syncStamps: stamps)
```

- [ ] **Step 4: 运行测试确认通过 + 既有回归**

Run: `cd client && ..\scripts\flutter.ps1 test`
Expected: 既有 376 项 + 新增 3 项全过。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/domain/entry.dart client/lib/src/data/local/sqlite_entry_repository.dart client/test/data/sqlite_sync_stamps_test.dart
git commit -m "feat(F013):schema v6字段级时间戳,add per-field sync stamps"
```

---

## Task 2: Entry↔SyncEntry 映射（纯函数）

**Files:**
- Create: `client/lib/src/domain/sync/entry_sync_map.dart`
- Test: `client/test/domain/sync/entry_sync_map_test.dart`

**Interfaces:**
- Consumes: `Entry`、`SyncEntry`、`FieldValue`、`mergeFieldLww`（sync_core）。
- Produces: `SyncEntry toSyncEntry(Entry)`（推：带 syncStamps 的字段）；`Entry applyRemote(Entry local, SyncEntry remote)`（拉：字段级 LWW 合并入 local，更新 syncStamps）。

- [ ] **Step 1: 写失败测试**

`client/test/domain/sync/entry_sync_map_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/sync/entry_sync_map.dart';
import 'package:sync_core/sync_core.dart';

Entry _e(String id, {String content = 'c', String? mood, List<String> tags = const [], int? deletedAt, Map<String,int> stamps = const {}}) {
  final now = 1000;
  return Entry(
    id: id, content: content,
    createdAt: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
    dayKey: '2026-11-03', deletedAt: deletedAt != null ? DateTime.fromMillisecondsSinceEpoch(deletedAt, isUtc: true) : null,
    mood: mood, tags: tags, syncStamps: stamps,
  );
}

void main() {
  group('toSyncEntry', () {
    test('Entry 映射为带时间戳的 SyncEntry', () {
      final e = _e('e1', content: 'hello', mood: 'happy', tags: ['a'], stamps: const {'content': 200, 'mood': 200, 'tags': 200});
      final s = toSyncEntry(e);
      expect(s.id, 'e1');
      expect(s.fields['content'], const FieldValue('hello', 200));
      expect(s.fields['mood'], const FieldValue('happy', 200));
      expect(s.fields['tags'], const FieldValue(const ['a'], 200));
    });
  });

  group('applyRemote', () {
    test('远端字段较新则覆盖，较旧则保留', () {
      final local = _e('e1', content: 'local', stamps: const {'content': 300, 'mood': 100});
      final remote = SyncEntry(id: 'e1', createdAt: 1000, fields: const {
        'content': FieldValue('remote-old', 200),
        'mood': FieldValue('excited', 200),
      });
      final merged = applyRemote(local, remote);
      expect(merged.content, 'local');       // 本地新，保留
      expect(merged.mood, 'excited');        // 远端新，覆盖
      expect(merged.syncStamps['content'], 300); // 本地戳不变
      expect(merged.syncStamps['mood'], 200);    // 远端戳更新
    });

    test('远端较新的字段覆盖并更新本地戳', () {
      final local = _e('e1', content: 'old', stamps: const {'content': 100});
      final remote = SyncEntry(id: 'e1', createdAt: 1000, fields: const {
        'content': FieldValue('new', 500),
      });
      final merged = applyRemote(local, remote);
      expect(merged.content, 'new');
      expect(merged.syncStamps['content'], 500);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && ..\scripts\flutter.ps1 test test/domain/sync/entry_sync_map_test.dart`
Expected: FAIL —— `toSyncEntry` 未定义。

- [ ] **Step 3: 写实现**

`client/lib/src/domain/sync/entry_sync_map.dart`：

```dart
import 'package:sync_core/sync_core.dart';

import '../entry.dart';

/// Entry → SyncEntry（推）：把 Entry 字段连同 syncStamps 组成字段级 patch。
/// 只输出 stamp > 0 的字段。
SyncEntry toSyncEntry(Entry e) {
  final fields = <String, FieldValue>{};
  void put(String name, Object? v, int stamp) {
    if (stamp > 0) fields[name] = FieldValue(v, stamp);
  }
  put('content', e.content, e.syncStamps['content'] ?? 0);
  put('mood', e.mood, e.syncStamps['mood'] ?? 0);
  put('tags', e.tags, e.syncStamps['tags'] ?? 0);
  put('deletedAt', e.deletedAt?.millisecondsSinceEpoch, e.syncStamps['deletedAt'] ?? 0);
  return SyncEntry(id: e.id, createdAt: e.createdAt.millisecondsSinceEpoch, fields: fields);
}

/// 拉：把远端 SyncEntry 字段级 LWW 合并入 local，更新 syncStamps。
/// 远端字段 t > 本地戳才应用；平局取远端（推送方）。
Entry applyRemote(Entry local, SyncEntry remote) {
  final stamps = <String, int>{...local.syncStamps};
  void set(String name, Object? newV, int remoteT) {
    final localT = local.syncStamps[name] ?? 0;
    if (remoteT >= localT) {
      stamps[name] = remoteT;
      // 值由调用方按字段名取；这里只更新戳
    }
  }
  // 逐字段比较并更新值
  String? content; String? mood; List<String> tags = local.tags; int? deletedAt = local.deletedAt?.millisecondsSinceEpoch;
  for (final f in remote.fields.entries) {
    final t = f.value.t;
    switch (f.key) {
      case 'content':
        if (t >= local.syncStamps['content'] ?? 0) { content = f.value.v as String; stamps['content'] = t; }
      case 'mood':
        if (t >= local.syncStamps['mood'] ?? 0) { mood = f.value.v as String?; stamps['mood'] = t; }
      case 'tags':
        if (t >= local.syncStamps['tags'] ?? 0) { tags = (f.value.v as List).cast<String>(); stamps['tags'] = t; }
      case 'deletedAt':
        if (t >= local.syncStamps['deletedAt'] ?? 0) {
          deletedAt = f.value.v as int?;
          stamps['deletedAt'] = t;
        }
    }
  }
  return Entry(
    id: local.id,
    content: content ?? local.content,
    createdAt: local.createdAt,
    updatedAt: local.updatedAt,
    dayKey: local.dayKey,
    deletedAt: deletedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(deletedAt, isUtc: true),
    mood: mood,
    tags: tags,
    photo: local.photo,
    syncStamps: stamps,
  );
}
```

> 注：switch 不带 break 在 Dart 3 默认穿透，上面故意让每个 case 独立判断（if 包裹），语义正确。若 analyze 报 fallthrough，给每个 case 加独立逻辑即可。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && ..\scripts\flutter.ps1 test test/domain/sync/entry_sync_map_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/domain/sync/entry_sync_map.dart client/test/domain/sync/entry_sync_map_test.dart
git commit -m "feat(F013):Entry同步映射,add entry sync mapping"
```

---

## Task 3: RemoteRepo + EmailPasswordProvider

**Files:**
- Modify: `client/pubspec.yaml`（加 `http`）
- Create: `client/lib/src/data/remote/remote_repo.dart`
- Create: `client/lib/src/data/remote/email_password_provider.dart`
- Test: `client/test/data/remote/remote_repo_test.dart`、`email_password_provider_test.dart`

**Interfaces:**
- Consumes: `SyncCodec`、`SyncPushBatch`、`SyncPullResponse`、`AuthProvider`、`AuthResult`（sync_core）。
- Produces: `RemoteRepo`（pull/push/register/login，注入 `http.Client` + baseUrl + SyncCodec）；`EmailPasswordProvider implements AuthProvider`（注入 http.Client + TokenStore）。

- [ ] **Step 1: 写失败测试**

`client/test/data/remote/remote_repo_test.dart`（用 `http` 的 `MockClient` 或注入 fake）：

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_diary/src/data/remote/remote_repo.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  group('RemoteRepo', () {
    test('pull 解析 cursor 与 entries', () async {
      final handler = (req) async {
        expect(req.url.toString(), endsWith('/sync?cursor=0'));
        return http.Response(
          jsonEncode({'cursor': 7, 'entries': []}), 200,
          headers: {'content-type': 'application/json'});
      };
      final repo = RemoteRepo(http.Client(), 'http://x', const SyncCodec(), handler: handler);
      final r = await repo.pull('tok', 0);
      expect(r.cursor, 7);
    });

    test('push 发送批次', () async {
      var pushed = false;
      final handler = (req) async {
        pushed = true;
        expect(req.method, 'POST');
        return http.Response('{"ok":true}', 200, headers: {'content-type': 'application/json'});
      };
      final repo = RemoteRepo(http.Client(), 'http://x', const SyncCodec(), handler: handler);
      await repo.push('tok', SyncPushBatch(patches: []));
      expect(pushed, isTrue);
    });

    test('register 返回 token', () async {
      final handler = (req) async => http.Response(
        jsonEncode({'userId': 'u1', 'token': 'tok'}), 200,
        headers: {'content-type': 'application/json'});
      final repo = RemoteRepo(http.Client(), 'http://x', const SyncCodec(), handler: handler);
      final r = await repo.register('a@b.com', 'pw');
      expect(r.token, 'tok');
    });
  });
}
```

`client/test/data/remote/email_password_provider_test.dart`：

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_diary/src/data/remote/email_password_provider.dart';

void main() {
  group('EmailPasswordProvider', () {
    test('login 成功返回 AuthResult 并持久化 token', () async {
      final handler = (req) async => http.Response(
        jsonEncode({'userId': 'u1', 'token': 'tok'}), 200,
        headers: {'content-type': 'application/json'});
      final store = _FakeTokenStore();
      final p = EmailPasswordProvider(http.Client(), 'http://x', store, handler: handler);
      final r = await p.login('a@b.com', 'pw');
      expect(r.token, 'tok');
      expect(store.value, 'tok');
    });

    test('current 从 store 读取', () async {
      final store = _FakeTokenStore(value: 'tok');
      final p = EmailPasswordProvider(http.Client(), 'http://x', store, handler: (r) async => http.Response('', 200));
      expect((await p.current())?.token, 'tok');
    });
  });
}

class _FakeTokenStore implements TokenStore {
  String? value;
  _FakeTokenStore({this.value});
  @override Future<String?> read() async => value;
  @override Future<void> write(String? t) async { value = t; }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && ..\scripts\flutter.ps1 test test/data/remote/`
Expected: FAIL —— `RemoteRepo` / `EmailPasswordProvider` 未定义。

- [ ] **Step 3: 写实现**

`client/pubspec.yaml` dependencies 加：
```yaml
  http: ^1.2.0
```

`client/lib/src/data/remote/remote_repo.dart`：

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sync_core/sync_core.dart';

/// 可选的 HTTP 处理替身，测试注入。
typedef HttpHandler = Future<http.Response> Function(http.Request request);

class RemoteRepo {
  RemoteRepo(this.client, this.baseUrl, this.codec, {this.handler});
  final http.Client client;
  final String baseUrl;
  final SyncCodec codec;
  final HttpHandler? handler;

  Future<http.Response> _send(http.Request req) {
    final h = handler;
    if (h != null) return h(req);
    return client.send(req);
  }

  Future<SyncPullResponse> pull(String token, int cursor) async {
    final req = http.Request('GET', Uri.parse('$baseUrl/sync?cursor=$cursor'));
    req.headers['authorization'] = 'Bearer $token';
    final r = await _send(req);
    return codec.decodePull(utf8.decode(r.body));
  }

  Future<void> push(String token, SyncPushBatch batch) async {
    final req = http.Request('POST', Uri.parse('$baseUrl/sync/batch'));
    req.headers['authorization'] = 'Bearer $token';
    req.headers['content-type'] = 'application/json';
    req.body = codec.encodePush(batch);
    await _send(req);
  }

  Future<AuthResult> register(String email, String password) async {
    final req = http.Request('POST', Uri.parse('$baseUrl/auth/register'));
    req.headers['content-type'] = 'application/json';
    req.body = jsonEncode({'email': email, 'password': password});
    final r = await _send(req);
    return _authResult(r);
  }

  Future<AuthResult?> login(String email, String password) async {
    final req = http.Request('POST', Uri.parse('$baseUrl/auth/login'));
    req.headers['content-type'] = 'application/json';
    req.body = jsonEncode({'email': email, 'password': password});
    final r = await _send(req);
    if (r.statusCode == 401) return null;
    return _authResult(r);
  }

  AuthResult _authResult(http.Response r) {
    final j = jsonDecode(utf8.decode(r.body)) as Map<String, dynamic>;
    return AuthResult(userId: j['userId'] as String, token: j['token'] as String);
  }
}
```

`client/lib/src/data/remote/email_password_provider.dart`：

```dart
import 'package:http/http.dart' as http;
import 'package:sync_core/sync_core.dart';
import 'remote_repo.dart';

abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String? token);
}

class EmailPasswordProvider implements AuthProvider {
  EmailPasswordProvider(this.client, this.baseUrl, this.tokenStore, {required this.handler});
  final http.Client client;
  final String baseUrl;
  final TokenStore tokenStore;
  final RemoteRepo._HttpHandler alias; // 占位，实际用 handler
}
```

> 上面 `EmailPasswordProvider` 的 `handler` 类型与 RemoteRepo 的 `HttpHandler` 一致。修正为直接复用：

```dart
class EmailPasswordProvider implements AuthProvider {
  EmailPasswordProvider(this.client, this.baseUrl, this.tokenStore, {this.handler});
  final http.Client client;
  final String baseUrl;
  final TokenStore tokenStore;
  final RemoteRepo._HttpHandler? handler; // 用 RemoteRepo 的替身类型
  RemoteRepo get _repo => RemoteRepo(client, baseUrl, const SyncCodec(), handler: handler);

  @override
  Future<AuthResult> register(String email, String password) async {
    final r = await _repo.register(email, password);
    await tokenStore.write(r.token);
    return r;
  }
  @override
  Future<AuthResult?> login(String email, String password) async {
    final r = await _repo.login(email, password);
    if (r != null) await tokenStore.write(r.token);
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
```

> `RemoteRepo._HttpHandler` 应导出为公共类型。把 `HttpHandler` 在 remote_repo.dart 里定义为顶层 typedef 并导出即可（已是顶层）。修正 EmailPasswordProvider 的 handler 类型为 `HttpHandler?`。

- [ ] **Step 4: 运行测试确认通过 + 既有回归**

Run: `cd client && ..\scripts\flutter.ps1 pub get && ..\scripts\flutter.ps1 test`
Expected: 既有 + 新增远程测试全过。

- [ ] **Step 5: 提交**

```bash
git add client/pubspec.yaml client/pubspec.lock client/lib/src/data/remote/ client/test/data/remote/
git commit -m "feat(F013):RemoteRepo与邮箱鉴权,add remote repo and email auth"
```

---

## Task 4: SyncEngine（脏队列/推拉/退避）

**Files:**
- Create: `client/lib/src/data/sync/sync_engine.dart`
- Test: `client/test/data/sync/sync_engine_test.dart`

**Interfaces:**
- Consumes: `LocalEntryRepository`、`RemoteRepo`、`AuthProvider`、`toSyncEntry`、`applyRemote`。
- Produces: `SyncEngine`（start/stop/trigger；推循环读脏→push；拉循环 pull→applyRemote 写 LocalRepo；退避重试；状态回调）。

- [ ] **Step 1: 写失败测试**

`client/test/data/sync/sync_engine_test.dart`（用 fake RemoteRepo + sqflite_common_ffi + fake AuthProvider）：

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/data/remote/remote_repo.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:sync_core/sync_core.dart';

class _FakeRemote {
  SyncPullResponse? nextPull;
  final List<SyncPushBatch> pushes = [];
  Future<SyncPullResponse> pull(String t, int c) async => nextPull ?? SyncPullResponse(cursor: c, entries: []);
  Future<void> push(String t, SyncPushBatch b) async { pushes.add(b); }
}

class _FakeAuth implements AuthProvider {
  @override Future<AuthResult> register(String e, String p) async => throw UnimplementedError();
  @override Future<AuthResult> login(String e, String p) async => AuthResult(userId: 'u1', token: 'tok');
  @override Future<AuthResult?> current() async => AuthResult(userId: 'u1', token: 'tok');
  @override Future<void> signOut() async {}
}

void main() {
  group('SyncEngine', () {
    test('push：脏条目推给 RemoteRepo', () async {
      final repo = SqliteEntryRepository(factory: sqfliteDatabaseFactory(), path: ':memory:');
      final remote = _FakeRemote();
      final engine = SyncEngine(repository: repo, remote: remote, auth: _FakeAuth(), now: () => DateTime.now());
      await repo.save(Entry(id: 'e1', content: 'hi', createdAt: DateTime.now(), updatedAt: DateTime.now(), dayKey: '2026-11-03'));
      await engine.pushOnce();
      expect(remote.pushes, hasLength(1));
      expect(remote.pushes.single.patches.single.id, 'e1');
      await repo.close();
    });

    test('pull：远端条目合并入本地', () async {
      final repo = SqliteEntryRepository(factory: sqfliteDatabaseFactory(), path: ':memory:');
      final remote = _FakeRemote();
      remote.nextPull = SyncPullResponse(cursor: 1, entries: [
        SyncEntry(id: 'e2', createdAt: 1000, fields: const {'content': FieldValue('remote', 5000)}),
      ]);
      final engine = SyncEngine(repository: repo, remote: remote, auth: _FakeAuth(), now: () => DateTime.now());
      await engine.pullOnce();
      final all = await repo.exportAll();
      expect(all.any((e) => e.id == 'e2' && e.content == 'remote'), isTrue);
      await repo.close();
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && ..\scripts\flutter.ps1 test test/data/sync/sync_engine_test.dart`
Expected: FAIL —— `SyncEngine` 未定义。

- [ ] **Step 3: 写实现**

`client/lib/src/data/sync/sync_engine.dart`：

```dart
import 'dart:async';

import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/local_entry_repository.dart';
import 'package:local_diary/src/domain/sync/entry_sync_map.dart';
import 'package:sync_core/sync_core.dart';

import '../remote/remote_repo.dart';

typedef NowFn = DateTime Function();

/// 同步引擎：LocalRepo 的异步旁路。推读脏→RemoteRepo.push；拉 RemoteRepo.pull→applyRemote 写 LocalRepo。
/// 本 Part 提供同步 pushOnce/pullOnce 供测试；触发循环（启动/前台/定时）在 Part 3b 接入 UI 生命周期。
class SyncEngine {
  SyncEngine({required this.repository, required this.remote, required this.auth, required this.now});
  final LocalEntryRepository repository;
  final RemoteRepo remote;
  final AuthProvider auth;
  final NowFn now;

  int _cursor = 0;

  Future<AuthResult?> _me() async {
    final r = await auth.current();
    return r;
  }

  /// 推一次：读全部未删条目，构批次推给服务端。成功后不清除 syncStamps
  /// （时间戳即「已同步」标记：服务端已含该戳的字段不会再被更旧的推覆盖）。
  Future<void> pushOnce() async {
    final me = await _me();
    if (me == null) return;
    final entries = await repository.exportAll();
    final patches = entries
        .where((e) => !e.isDeleted)
        .map((e) => EntryPatch(id: e.id, createdAt: e.createdAt.millisecondsSinceEpoch, fields: toSyncEntry(e).fields))
        .toList();
    if (patches.isEmpty) return;
    await remote.push(me.token, SyncPushBatch(patches: patches));
  }

  /// 拉一次：拉远端变更，字段级 LWW 合并入本地，推进 cursor。
  Future<void> pullOnce() async {
    final me = await _me();
    if (me == null) return;
    final result = await remote.pull(me.token, _cursor);
    _cursor = result.cursor;
    for (final remoteEntry in result.entries) {
      final existing = (await repository.exportAll()).firstWhere((e) => e.id == remoteEntry.id, orElse: () => null);
      if (existing == null) {
        await repository.save(_fromSyncEntry(remoteEntry));
      } else {
        await repository.save(applyRemote(existing, remoteEntry));
      }
    }
  }

  Entry _fromSyncEntry(SyncEntry s) {
    final fields = s.fields;
    return Entry(
      id: s.id,
      content: (fields['content']?.v as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(s.createdAt, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(s.createdAt, isUtc: true),
      dayKey: _dayKey(DateTime.fromMillisecondsSinceEpoch(s.createdAt, isUtc: true)),
      deletedAt: fields['deletedAt']?.v == null ? null : DateTime.fromMillisecondsSinceEpoch(fields['deletedAt']!.v as int, isUtc: true),
      mood: fields['mood']?.v as String?,
      tags: (fields['tags']?.v as List?)?.cast<String>() ?? const [],
      syncStamps: fields.map((k, v) => MapEntry(k, v.t)),
    );
  }

  String _dayKey(DateTime dt) => '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
```

> 注：`pushOnce` 推全部未删条目（最小实现）；生产可改为只推脏字段（基于 syncStamps 与服务端已知戳）。退避重试与触发循环在 Part 3b 接入。

- [ ] **Step 4: 运行测试确认通过 + 既有回归**

Run: `cd client && ..\scripts\flutter.ps1 test`
Expected: 既有 + 新增同步引擎测试全过。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/data/sync/ client/test/data/sync/
git commit -m "feat(F013):SyncEngine推拉,add sync engine push and pull"
```

---

## 自检

- **Spec 覆盖**：spec 第 4 节（SyncEngine 三循环）、第 5 节（字段级合并）、第 7 节（数据流）由 Task 1-4 覆盖；退避重试与触发循环明确标注在 Part 3b 接入（本 Part 提供 pushOnce/pullOnce 同步入口）。
- **占位符**：无 TBD/TODO。EmailPasswordProvider 的 handler 类型已统一为 RemoteRepo 的 HttpHandler。
- **类型一致**：toSyncEntry/applyRemote/SyncEngine 与 sync_core 的 SyncEntry/FieldValue/SyncPushBatch 签名一致。

## 执行交接

本计划保存到 `docs/superpowers/plans/云同步-客户端同步引擎-client-sync-engine.md`。UI（鉴权/认领/同步状态/生命周期触发）为 Part 3b，待本 Part 核心完成后编写。
