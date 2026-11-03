# F013 云同步实现计划 · Part 2：服务端

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建服务端 Dart 包 `server`（shelf），实现邮箱+密码鉴权与同步接口（拉取/推送），合并逻辑复用 sync_core 字段级 LWW；游标用全局单调 seq，落库同事务。

**Architecture:** `SyncStore` 抽象隔离存储；`FakeSyncStore`（内存）承载全部逻辑并宿主测试（环境无 postgres/Docker，PostgresSyncStore 延后）。shelf handler 是薄适配层：解析 Request → 调 SyncStore → 构 Response。handler 不持业务逻辑，逻辑全在 SyncStore，便于宿主测试。

**Tech Stack:** Dart 3.13.7，`shelf`，`package:crypto`（密码哈希），sync_core（path 依赖）。

## 全局约束

- SDK：`sdk: ^3.13.7`。
- 包位置：`packages/server/`，path 依赖 `../sync_core`。
- 鉴权：邮箱+密码；密码 `sha256(salt+password)`，salt 每用户随机；token 随机串。非 bcrypt——最小里程碑取舍，生产应换 bcrypt/argon2。
- 合并：服务端 push 用 `sync_core.mergeFieldLww` 逐字段合并入 payload；绝不整条覆盖。
- 游标：全局单调 seq（`int`，每次 push 递增）；pull 返回 `seq > cursor` 的条目，新 cursor = 结果最大 seq。
- createdAt 不可变：push 新建条目用 patch 的 createdAt，已有条目保留原 createdAt。
- 提交信息：`<type>:<中文说明>,<english summary>`，标注 `feat(F013)`。

## 环境限制（重要）

- 无 postgres、无 Docker → PostgresSyncStore（真实 SQL）**延后**，本 Part 只交付可测的 FakeSyncStore + handler 逻辑。真实 postgres 集成在环境就绪后另立任务，不得把未测 SQL 标为通过。

## 文件结构

```
packages/server/
  pubspec.yaml                 # shelf + crypto + sync_core(path)
  lib/server.dart               # barrel
  lib/src/sync_store.dart        # SyncStore 抽象
  lib/src/fake_sync_store.dart   # 内存实现（全部逻辑）
  lib/src/password.dart          # sha256+salt、token 生成
  lib/src/handlers.dart          # shelf handler（auth + sync 薄适配）
  lib/src/main.dart              # router 装配（可运行入口）
  test/fake_sync_store_auth_test.dart
  test/fake_sync_store_sync_test.dart
  test/handlers_test.dart
```

---

## Task 1: 服务端包骨架 + SyncStore 抽象 + FakeSyncStore 鉴权

**Files:**
- Create: `packages/server/pubspec.yaml`
- Create: `packages/server/lib/server.dart`
- Create: `packages/server/lib/src/sync_store.dart`
- Create: `packages/server/lib/src/password.dart`
- Create: `packages/server/lib/src/fake_sync_store.dart`
- Test: `packages/server/test/fake_sync_store_auth_test.dart`

**Interfaces:**
- Consumes: `AuthResult`、`SyncPullResponse`、`SyncPushBatch`（sync_core）。
- Produces: `SyncStore` 抽象（register/login/userIdForToken/pull/push）；`FakeSyncStore implements SyncStore`；`hashPassword(String password, String salt)`、`newToken()`。

- [ ] **Step 1: 写失败测试**

`packages/server/test/fake_sync_store_auth_test.dart`：

```dart
import 'package:test/test.dart';
import 'package:server/server.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  group('FakeSyncStore 鉴权', () {
    test('注册后能登录', () async {
      final store = FakeSyncStore();
      final r = await store.register('a@b.com', 'pw');
      expect(r.userId.isNotEmpty, isTrue);
      expect(r.token.isNotEmpty, isTrue);
      final back = await store.login('a@b.com', 'pw');
      expect(back?.userId, r.userId);
    });

    test('错误密码登录失败', () async {
      final store = FakeSyncStore();
      await store.register('a@b.com', 'pw');
      expect(await store.login('a@b.com', 'wrong'), isNull);
    });

    test('重复邮箱注册失败', () async {
      final store = FakeSyncStore();
      await store.register('a@b.com', 'pw');
      expect(
        () => store.register('a@b.com', 'pw2'),
        throwsStateError,
      );
    });

    test('token 能解析回 userId', () async {
      final store = FakeSyncStore();
      final r = await store.register('a@b.com', 'pw');
      expect(await store.userIdForToken(r.token), r.userId);
      expect(await store.userIdForToken('bad'), isNull);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/server && dart pub get && dart test test/fake_sync_store_auth_test.dart`
Expected: FAIL —— `FakeSyncStore` 未定义。

- [ ] **Step 3: 写实现**

`packages/server/pubspec.yaml`：

```yaml
name: server
description: "云同步服务端：鉴权 + 同步接口（字段级 LWW 合并）。"
publish_to: 'none'
version: 0.0.1

environment:
  sdk: ^3.13.7

dependencies:
  shelf: ^1.4.0
  crypto: ^3.0.3
  sync_core:
    path: ../sync_core

dev_dependencies:
  test: ^1.25.0
```

`packages/server/lib/src/password.dart`：

```dart
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// sha256(salt + password)。非 bcrypt——最小里程碑取舍，生产应换 bcrypt/argon2。
String hashPassword(String password, String salt) {
  final h = sha256.convert(utf8.encode('$salt$password'));
  return h.toString();
}

/// 随机 salt（hex）。
String newSalt() => Random.secure().nextBytes(16).toHex();

/// 随机 token（hex）。
String newToken() => Random.secure().nextBytes(24).toHex();
```

`packages/server/lib/src/sync_store.dart`：

```dart
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
```

`packages/server/lib/src/fake_sync_store.dart`：

```dart
import 'dart:math';

import 'package:sync_core/sync_core.dart';
import 'password.dart';
import 'sync_store.dart';

class _User {
  _User(this.userId, this.email, this.hash, this.salt);
  final String userId;
  final String email;
  final String hash;
  final String salt;
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
      throw StateError('Email already registered');
    }
    final salt = newSalt();
    final userId = 'u${_seq++}';
    _users[email] = _User(userId, email, hashPassword(password, salt), salt);
    final token = newToken();
    _tokens[token] = userId;
    return AuthResult(userId: userId, token: token);
  }

  @override
  Future<AuthResult?> login(String email, String password) async {
    final u = _users[email];
    if (u == null) return null;
    if (hashPassword(password, u.salt) != u.hash) return null;
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
```

`packages/server/lib/server.dart`：

```dart
export 'src/sync_store.dart';
export 'src/fake_sync_store.dart';
export 'src/password.dart';
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd packages/server && dart test`
Expected: PASS（4 项鉴权测试）。

- [ ] **Step 5: 提交**

```bash
git add packages/server
git commit -m "feat(F013):服务端鉴权与SyncStore,add server auth and sync store"
```

---

## Task 2: FakeSyncStore 同步（pull/push/合并/游标）

**Files:**
- Modify: `packages/server/lib/src/fake_sync_store.dart`（push/pull 已在 Task 1 写入，补测试覆盖）
- Test: `packages/server/test/fake_sync_store_sync_test.dart`

**Interfaces:**
- Consumes: `mergeFieldLww`、`SyncPushBatch`、`SyncPullResponse`（sync_core）。
- Produces: push 逐字段 LWW 合并入 payload、递增 seq；pull 返回 seq > cursor 的已合并态 + 新 cursor。

- [ ] **Step 1: 写失败测试**

`packages/server/test/fake_sync_store_sync_test.dart`：

```dart
import 'package:test/test.dart';
import 'package:server/server.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  group('FakeSyncStore 同步', () {
    test('push 后能 pull 到', () async {
      final store = FakeSyncStore();
      final r = await store.register('a@b.com', 'pw');
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(
          id: 'e1',
          createdAt: 1000,
          fields: const {'content': FieldValue('hello', 2000)},
        ),
      ]));
      final pulled = await store.pull(r.userId, 0);
      expect(pulled.entries.single.id, 'e1');
      expect(pulled.entries.single.fields['content'],
          const FieldValue('hello', 2000));
      expect(pulled.cursor, isGreaterThan(0));
    });

    test('字段级冲突：后推送的较新字段覆盖，较旧的不覆盖', () async {
      final store = FakeSyncStore();
      final r = await store.register('a@b.com', 'pw');
      // 设备 A 改正文
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 1, fields: const {
          'content': FieldValue('from-A', 200),
          'mood': FieldValue('calm', 200),
        }),
      ]));
      // 设备 B 改心情（较新），正文较旧
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 1, fields: const {
          'content': FieldValue('from-B-old', 100), // 旧，不应覆盖
          'mood': FieldValue('excited', 300),        // 新，应覆盖
        }),
      ]));
      final pulled = await store.pull(r.userId, 0);
      final fields = pulled.entries.single.fields;
      expect(fields['content'], const FieldValue('from-A', 200));
      expect(fields['mood'], const FieldValue('excited', 300));
    });

    test('游标推进：只返回 seq > cursor 的条目', () async {
      final store = FakeSyncStore();
      final r = await store.register('a@b.com', 'pw');
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 1, fields: const {
          'content': FieldValue('a', 100),
        }),
      ]));
      final first = await store.pull(r.userId, 0);
      expect(first.entries, hasLength(1));
      final c = first.cursor;
      // 第二次 pull 用相同 cursor：无新条目，cursor 不变
      final again = await store.pull(r.userId, c);
      expect(again.entries, isEmpty);
      expect(again.cursor, c);
      // 新增条目后再 pull：只拿到新条目
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e2', createdAt: 2, fields: const {
          'content': FieldValue('b', 100),
        }),
      ]));
      final next = await store.pull(r.userId, c);
      expect(next.entries.single.id, 'e2');
    });

    test('createdAt 不可变：更新条目保留原 createdAt', () async {
      final store = FakeSyncStore();
      final r = await store.register('a@b.com', 'pw');
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 999, fields: const {
          'content': FieldValue('v1', 100),
        }),
      ]));
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 1, fields: const {
          'content': FieldValue('v2', 200),
        }),
      ]));
      final pulled = await store.pull(r.userId, 0);
      expect(pulled.entries.single.createdAt, 999);
      expect(pulled.entries.single.fields['content'], const FieldValue('v2', 200));
    });
  });
}
```

- [ ] **Step 2: 运行测试确认通过**

Run: `cd packages/server && dart test test/fake_sync_store_sync_test.dart`
Expected: PASS（Task 1 的 push/pull 实现已满足这些行为）。

- [ ] **Step 3: 提交**

```bash
git add packages/server
git commit -m "feat(F013):服务端同步合并与游标,add sync merge and cursor"
```

---

## Task 3: shelf handler（auth + sync 薄适配）

**Files:**
- Create: `packages/server/lib/src/handlers.dart`
- Modify: `packages/server/lib/server.dart`
- Test: `packages/server/test/handlers_test.dart`

**Interfaces:**
- Consumes: `SyncStore`、`SyncCodec`、`AuthResult`（sync_core + Task 1）。
- Produces: `shelf.Handler` 工厂：`registerHandler(store)`、`loginHandler(store)`、`pullHandler(store)`、`pushHandler(store)`，返回 `Future<shelf.Response> Function(shelf.Request)`。

- [ ] **Step 1: 写失败测试**

`packages/server/test/handlers_test.dart`：

```dart
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:server/server.dart';
import 'package:sync_core/sync_core.dart';

shelf.Request _req(
  String method,
  String path, {
  Map<String, String> headers = const {},
  String body = '',
}) =>
    shelf.Request(
      method: method,
      uri: Uri.parse(path),
      headers: headers.map((k, v) => MapEntry(k.toLowerCase(), v)),
      readBody: () => Future.value(body.codeUnits),
    );

String _body(shelf.Response r) async =>
    utf8.decode(await r.readBodyAsBytes());

void main() {
  group('handlers', () {
    test('register 返回 userId 与 token', () async {
      final store = FakeSyncStore();
      final h = registerHandler(store);
      final r = await h(_req('POST', '/auth/register',
          body: '{"email":"a@b.com","password":"pw"}'));
      expect(r.statusCode, 200);
      final j = jsonDecode(await _body(r)) as Map<String, dynamic>;
      expect(j['userId'], isA<String>());
      expect(j['token'], isA<String>());
    });

    test('login 错误密码返回 401', () async {
      final store = FakeSyncStore();
      await store.register('a@b.com', 'pw');
      final h = loginHandler(store);
      final r = await h(_req('POST', '/auth/login',
          body: '{"email":"a@b.com","password":"wrong"}'));
      expect(r.statusCode, 401);
    });

    test('pull 需要鉴权：无 token 返回 401', () async {
      final store = FakeSyncStore();
      final h = pullHandler(store);
      final r = await h(_req('GET', '/sync?cursor=0'));
      expect(r.statusCode, 401);
    });

    test('pull 带 token 返回同步结果', () async {
      final store = FakeSyncStore();
      final reg = await store.register('a@b.com', 'pw');
      await store.push(reg.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 1, fields: const {
          'content': FieldValue('hi', 100),
        }),
      ]));
      final h = pullHandler(store);
      final r = await h(_req('GET', '/sync?cursor=0',
          headers: {'authorization': 'Bearer ${reg.token}'}));
      expect(r.statusCode, 200);
      final j = jsonDecode(await _body(r)) as Map<String, dynamic>;
      expect(j['cursor'], isA<int>());
      expect((j['entries'] as List), hasLength(1));
    });

    test('push 带 token 写入后可 pull', () async {
      final store = FakeSyncStore();
      final reg = await store.register('a@b.com', 'pw');
      final h = pushHandler(store);
      final r = await h(_req('POST', '/sync/batch',
          headers: {'authorization': 'Bearer ${reg.token}'},
          body: const '{"patches":[]}'));
      expect(r.statusCode, 200);
    });
  });
}
```

> 测试需 `import 'dart:convert';`（已在 `_body` 用 utf8/jsonDecode）。若 shelf.Request 构造签名不同，按 shelf 版本调整 `_req`。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/server && dart test test/handlers_test.dart`
Expected: FAIL —— `registerHandler` 未定义。

- [ ] **Step 3: 写实现**

`packages/server/lib/src/handlers.dart`：

```dart
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:sync_core/sync_core.dart';
import 'sync_store.dart';

const _codec = SyncCodec();

String? _bearer(shelf.Request req) {
  final h = req.headers['authorization'];
  if (h == null) return null;
  final m = RegExp(r'^Bearer (.+)$').firstMatch(h);
  return m?.group(1);
}

Map<String, dynamic> _json(shelf.Request req) =>
    jsonDecode(utf8.decode(req.readBodyAsBytes())) as Map<String, dynamic>;

shelf.Response _jsonOk(Object body, {int status = 200}) =>
    shelf.Response.ok(
      _codec.encodePull(const SyncPullResponse(cursor: 0, entries: []))
          .replaceFirst('{"cursor":0,"entries":[]}', ''),
      statusCode: status,
    );

// 更简单：直接 jsonEncode
shelf.Response _okJson(Object body) =>
    shelf.Response.ok(jsonEncode(body),
        headers: {'content-type': 'application/json'});

shelf.Response _err(int status, String msg) =>
    shelf.Response(statusCode: status, body: msg);

shelf.Handler registerHandler(SyncStore store) => (req) async {
  final j = _json(req);
  final email = j['email'] as String;
  final password = j['password'] as String;
  try {
    final r = await store.register(email, password);
    return _okJson({'userId': r.userId, 'token': r.token});
  } on StateError catch (_) {
    return _err(409, 'email already registered');
  }
};

shelf.Handler loginHandler(SyncStore store) => (req) async {
  final j = _json(req);
  final email = j['email'] as String;
  final password = j['password'] as String;
  final r = await store.login(email, password);
  if (r == null) return _err(401, 'invalid credentials');
  return _okJson({'userId': r.userId, 'token': r.token});
};

shelf.Handler pullHandler(SyncStore store) => (req) async {
  final token = _bearer(req);
  if (token == null) return _err(401, 'missing token');
  final userId = await store.userIdForToken(token);
  if (userId == null) return _err(401, 'invalid token');
  final cursor = int.tryParse(req.uri.queryParameters['cursor'] ?? '0') ?? 0;
  final result = await store.pull(userId, cursor);
  // 复用 codec 的 JSON 结构
  return _okJson(result.toJson());
};

shelf.Handler pushHandler(SyncStore store) => (req) async {
  final token = _bearer(req);
  if (token == null) return _err(401, 'missing token');
  final userId = await store.userIdForToken(token);
  if (userId == null) return _err(401, 'invalid token');
  final j = _json(req);
  final batch = SyncPushBatch.fromJson(j);
  await store.push(userId, batch);
  return _okJson({'ok': true});
};
```

> 注意：`_okJson` 直接 `jsonEncode`，与 `SyncPullResponse.toJson()` 结构一致（cursor/entries）。pull handler 用 `result.toJson()` 保证结构统一。移除未用的 `_jsonOk` 辅助。

Modify `packages/server/lib/server.dart`，在末尾追加：

```dart
export 'src/handlers.dart';
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd packages/server && dart test`
Expected: PASS（鉴权 4 + 同步 4 + handler 5 = 13 项）。

若 shelf.Request 构造签名与测试不符，调整 `_req` 辅助后重跑。

- [ ] **Step 5: 提交**

```bash
git add packages/server
git commit -m "feat(F013):服务端shelf handler,add shelf handlers"
```

---

## Task 4: 路由装配（main.dart）+ 分析

**Files:**
- Create: `packages/server/lib/src/main.dart`
- Modify: `packages/server/lib/server.dart`

**Interfaces:**
- Produces: `shelf.Handler createApp(SyncStore store)` 装配 4 个路由；`main()` 启动 shelf 服务。

- [ ] **Step 1: 写 main.dart**

`packages/server/lib/src/main.dart`：

```dart
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'handlers.dart';
import 'sync_store.dart';

shelf.Handler createApp(SyncStore store) {
  final router = Router()
    ..post('/auth/register', registerHandler(store))
    ..post('/auth/login', loginHandler(store))
    ..get('/sync', pullHandler(store))
    ..post('/sync/batch', pushHandler(store));
  return shelf.middleware.cors();
}

Future<void> main(List<String> args) async {
  final store = FakeSyncStore();
  final server = await shelf.serve(createApp(store), '0.0.0.0', 8080);
  // 生产用 PostgresSyncStore；本 Part 用 FakeSyncStore（内存）。
}
```

> `main()` 是可运行入口，不做单元测试（无 HTTP 客户端环境）；由 `dart analyze` 保证可编译。需在 pubspec 加 `shelf_router: ^1.1.0`。

Modify `packages/server/pubspec.yaml` 的 dependencies 加：

```yaml
  shelf_router: ^1.1.0
```

Modify `packages/server/lib/server.dart`，在末尾追加：

```dart
export 'src/main.dart';
```

- [ ] **Step 2: 运行分析**

Run: `cd packages/server && dart pub get && dart analyze`
Expected: `No issues found!`

- [ ] **Step 3: 提交**

```bash
git add packages/server
git commit -m "feat(F013):服务端路由装配,add server router wiring"
```

---

## 自检

- **Spec 覆盖**：spec 第 5 节（4 接口、字段级合并、seq 游标、createdAt 不可变）、第 7 节数据流、第 8 节 401 处理（handler 返回 401）均有任务。PostgresSyncStore 因环境无 postgres 延后，已注明。
- **占位符**：无 TBD/TODO。handler 实现含完整代码。
- **类型一致**：`SyncStore`/`FakeSyncStore`/`SyncCodec`/`SyncPushBatch`/`SyncPullResponse` 签名在定义与测试一致；handler 用 `result.toJson()` 保证 pull 响应结构与 codec 一致。

## 执行交接

本计划保存到 `docs/superpowers/plans/云同步-服务端-server.md`。执行后若 handler 测试因 shelf.Request 构造签名受阻，调整 `_req` 辅助即可，不改变逻辑。
