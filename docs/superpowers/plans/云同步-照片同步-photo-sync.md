# F013 云同步实现计划 · Part 4：照片同步

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让随手拍的照片跨设备同步：Entry 加 photoKey（COS key，同步字段），BLOB photo 留本地；FakeCos 实现 CosGateway；映射 'photo' 字段=photoKey；SyncEngine push 上传设 key、pull 下载 BLOB。

**Architecture:** 照片是 BLOB，不直接走字段级 LWW——经服务端代理 COS：本地 photo BLOB → 上传 COS 得 key → sync 字段 'photo' 存 key → 其他设备拉到 key → 下载 BLOB 显示。FakeCos（本地文件系统）开发期用；真机腾讯云 COS 延后。

**Tech Stack:** Dart/Flutter 3.13.7，`dart:crypto`（sha256 key），sync_core `CosGateway`，sqflite_common_ffi（宿主测试）。

## 全局约束

- SDK：`sdk: ^3.13.7`。
- schema v7：entries 加 `photo_key TEXT`，迁移幂等。
- Entry.photoKey：String?（COS key，同步字段）。Entry.photo：Uint8List?（BLOB，本地缓存，不同步）。
- sync 字段：content/mood/tags/deletedAt/photo（photo=photoKey）。
- FakeCos：本地文件系统实现 CosGateway（upload 写本地目录返回 sha256 key；download 读本地；presign 返回假 URL）。
- 架构铁律：UI 不碰 RemoteRepo；写入走 LocalRepo；Domain 不依赖框架/SDK。
- 提交信息中英结合，标注 `feat(F013)`。

## 文件结构

```
client/lib/src/domain/entry.dart              # 加 photoKey
client/lib/src/data/local/sqlite_entry_repository.dart  # v7 迁移 + photoKey 读写 + _computeStamps 加 photo
client/lib/src/domain/sync/entry_sync_map.dart  # toSyncEntry/applyRemote 加 photo
client/lib/src/data/sync/sync_engine.dart       # CosGateway 注入；push 上传设 key；pull 下载 BLOB
client/lib/src/data/sync/fake_cos.dart           # FakeCos（本地文件系统）
client/test/...
```

---

## Task 1: schema v7 photo_key + Entry.photoKey + 仓储读写

**Files:**
- Modify: `client/lib/src/domain/entry.dart`（加 photoKey）
- Modify: `client/lib/src/data/local/sqlite_entry_repository.dart`（v7 迁移 + photoKey 列 + _computeStamps 加 photo + _toEntry 解析）
- Modify: `client/lib/src/domain/local_entry_repository.dart`（无新接口，photoKey 随 Entry 走）
- Test: `client/test/data/sqlite_photo_key_test.dart`

**Interfaces:**
- Produces: `Entry.photoKey`（String?）；仓储 save/saveMerged 持久化 photo_key；_computeStamps 对 photoKey 变化打 'photo' 戳；_toEntry 解析 photo_key。

- [ ] **Step 1: 写失败测试**

`client/test/data/sqlite_photo_key_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

Future<SqliteEntryRepository> _open() async =>
    SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');

void main() {
  test('photoKey 持久化与读回', () async {
    final repo = await _open();
    final now = DateTime.now().toUtc();
    await repo.save(Entry(
      id: 'e1', content: 'x', createdAt: now, updatedAt: now, dayKey: '2026-11-03',
      photoKey: 'key-abc',
    ));
    final all = await repo.exportAll();
    expect(all.single.photoKey, 'key-abc');
    await repo.close();
  });

  test('photoKey 变化打 photo 时间戳', () async {
    final repo = await _open();
    final t1 = DateTime.now().toUtc().millisecondsSinceEpoch;
    await repo.save(Entry(id: 'e1', content: 'x', createdAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true), dayKey: '2026-11-03'));
    // 设 photoKey
    final t2 = t1 + 1000;
    await repo.save(Entry(id: 'e1', content: 'x', createdAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(t2, isUtc: true), dayKey: '2026-11-03', photoKey: 'key-1'));
    final all = await repo.exportAll();
    expect(all.single.syncStamps['photo'], greaterThan(0));
    await repo.close();
  });
}
```

> 若 `databaseFactoryFfi` 未导入，用 `sqfliteFfiInit()` + `databaseFactoryFfi`（对齐既有测试模式）。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && ..\scripts\flutter.ps1 test test/data/sqlite_photo_key_test.dart`
Expected: FAIL —— `photoKey` 字段不存在。

- [ ] **Step 3: 写实现**

Modify `entry.dart`，Entry 加 `photoKey`：
```dart
this.photoKey,   // 新增：COS key，同步字段；photo BLOB 留本地不同步
```
（在 photo 字段后加 photoKey，构造参数与字段声明都要加。）

Modify `sqlite_entry_repository.dart`：
- schema version 6→7；onUpgrade 加 v7 迁移（幂等 `ALTER TABLE ADD COLUMN photo_key TEXT`）；onCreate CREATE TABLE 加 `photo_key TEXT`。
- `save`/`saveMerged` 的 UPDATE/INSERT 都加 `'photo_key': entry.photoKey`。
- `_computeStamps` 加：`bump('photo', e.photoKey, existing?.photoKey)`（photoKey 变化才打 photo 戳）。
- `_toEntry` 加 `photoKey: row['photo_key'] as String?`。
- `importAll` 的 insert/update 加 `'photo_key': decision.entry.photoKey`（与既有 mood/tags 同口径）。

- [ ] **Step 4: 运行测试确认通过 + 既有回归**

Run: `cd client && ..\scripts\flutter.ps1 test`
Expected: 新测试通过 + 既有 417 项不回归。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/domain/entry.dart client/lib/src/data/local/sqlite_entry_repository.dart client/test/data/sqlite_photo_key_test.dart
git commit -m "feat(F013):schema v7 photoKey,add photo_key column for sync"
```

---

## Task 2: photo 映射 + FakeCos

**Files:**
- Create: `client/lib/src/data/sync/fake_cos.dart`
- Modify: `client/lib/src/domain/sync/entry_sync_map.dart`（toSyncEntry/applyRemote 加 photo）
- Test: `client/test/domain/sync/entry_sync_map_photo_test.dart`、`client/test/data/sync/fake_cos_test.dart`

**Interfaces:**
- Consumes: `Entry.photoKey`、`CosGateway`（sync_core）。
- Produces: `FakeCos implements CosGateway`（本地文件系统：upload→sha256 key 写本地目录；download 读本地；presign 假 URL）；`toSyncEntry` 加 'photo' 字段=photoKey（仅 photoKey!=null）；`applyRemote` 加 'photo' 字段→photoKey。

- [ ] **Step 1: 写失败测试**

`client/test/data/sync/fake_cos_test.dart`：
```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/fake_cos.dart';

void main() {
  test('FakeCos 上传后能下载同内容', () async {
    final oss = FakeCos();
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final key = await oss.upload(bytes);
    expect(key, isA<String>());
    final back = await oss.download(key);
    expect(back, bytes);
    await oss.close();
  });
  test('presign 返回非空 URL', () async {
    final oss = FakeCos();
    final key = await oss.upload(Uint8List.fromList([1]));
    expect(await oss.presign(key), isA<String>());
    await oss.close();
  });
}
```

`client/test/domain/sync/entry_sync_map_photo_test.dart`：
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/sync/entry_sync_map.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  test('toSyncEntry 含 photoKey 时输出 photo 字段', () {
    final e = Entry(id: 'e1', content: 'x', createdAt: DateTime.now(), updatedAt: DateTime.now(),
      dayKey: '2026-11-03', photoKey: 'key-1', syncStamps: const {'photo': 5000});
    final s = toSyncEntry(e);
    expect(s.fields['photo'], const FieldValue('key-1', 5000));
  });
  test('applyRemote 用远端 photo 覆盖本地 photoKey', () {
    final local = Entry(id: 'e1', content: 'x', createdAt: DateTime.now(), updatedAt: DateTime.now(),
      dayKey: '2026-11-03', photoKey: 'old', syncStamps: const {'photo': 100});
    final remote = SyncEntry(id: 'e1', createdAt: 1000, fields: const {'photo': FieldValue('new-key', 500)});
    final merged = applyRemote(local, remote);
    expect(merged.photoKey, 'new-key');
    expect(merged.syncStamps['photo'], 500);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && ..\scripts\flutter.ps1 test test/data/sync/fake_cos_test.dart test/domain/sync/entry_sync_map_photo_test.dart`
Expected: FAIL —— `FakeCos`/photo 映射未定义。

- [ ] **Step 3: 写实现**

`fake_cos.dart`：
```dart
import 'dart:convert';
import 'dart:crypto';
import 'dart:io';
import 'dart:typed_data';
import 'package:sync_core/sync_core.dart';

/// 本地文件系统实现 CosGateway（开发/测试用）。upload 写临时目录返回 sha256 key；
/// download 读临时目录；presign 返回假 URL。不依赖任何云 SDK。
class FakeCos implements CosGateway {
  FakeCos({this.dir});
  final Directory? dir;
  late Directory _root;
  void _ensure() {
    if (_root.existsSync()) return;
    _root = dir ?? Directory.systemTemp.createTempSync('fakecos');
  }
  @override
  Future<String> upload(Uint8List bytes) async {
    _ensure();
    final h = sha256.convert(bytes).toString();
    await File('$_root/$h').writeAsBytes(bytes);
    return h;
  }
  @override
  Future<Uint8List> download(String key) async {
    _ensure();
    return Uint8List.fromList(await File('$_root/$key').readAsBytes());
  }
  @override
  Future<String> presign(String key) async => 'fake://$_root/$key';
  Future<void> close() async {
    if (_root.existsSync()) await Directory.fromUri(Uri.parse('file://$_root')).delete(recursive: true);
  }
}
```

> `Directory.systemTemp.createTempSync` + `writeAsBytes`/`readAsBytes`。若 `dir` 传入则用之。

Modify `entry_sync_map.dart`：
- `toSyncEntry` 的 `put` 辅助后加：`put('photo', e.photoKey, e.syncStamps['photo'] ?? 0);`（photoKey!=null 时 put 内会因 stamp>0 输出；photoKey==null 时 v=null 但 stamp 可能>0——若 photoKey 为 null 但 stamp>0（曾设过后清除），输出 FieldValue(null, stamp) 表示「无照片」，这是正确的删除语义）。
- `applyRemote` 加 `case 'photo'`（或 if/else 分支）：`if (t >= local.syncStamps['photo'] ?? 0) { photoKey = f.value.v as String?; stamps['photo'] = t; }`。photoKey 初值 = `local.photoKey`。

- [ ] **Step 4: 运行测试确认通过 + 既有回归**

Run: `cd client && ..\scripts\flutter.ps1 test`
Expected: 新测试通过 + 既有不回归。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/data/sync/fake_cos.dart client/lib/src/domain/sync/entry_sync_map.dart client/test/data/sync/fake_cos_test.dart client/test/domain/sync/entry_sync_map_photo_test.dart
git commit -m "feat(F013):FakeCos与照片映射,add fake cos and photo mapping"
```

---

## Task 3: SyncEngine 照片上传（push）+ 下载（pull）

**Files:**
- Modify: `client/lib/src/data/sync/sync_engine.dart`（注入 CosGateway；push 上传设 key；pull 下载 BLOB）
- Test: `client/test/data/sync/sync_engine_photo_test.dart`

**Interfaces:**
- Consumes: `CosGateway`、`Entry.photo`/`photoKey`、`FakeCos`。
- Produces: `SyncEngine({required CosGateway cos, ...})`；`pushOnce` 上传无 key 的 photo 设 photoKey；`pullOnce` 下载 photoKey 的 BLOB 设 photo。

- [ ] **Step 1: 写失败测试**

`client/test/data/sync/sync_engine_photo_test.dart`：
```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';
import 'package:local_diary/src/data/sync/fake_cos.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:sync_core/sync_core.dart';

class _FakeRemote implements SyncRemote {
  SyncPullResponse? nextPull;
  @override Future<SyncPullResponse> pull(String t, int c) async => nextPull ?? SyncPullResponse(cursor: c, entries: []);
  @override Future<void> push(String t, SyncPushBatch b) async {}
}
class _FakeAuth implements AuthProvider {
  @override Future<AuthResult> register(String e, String p) async => throw UnimplementedError();
  @override Future<AuthResult> login(String e, String p) async => AuthResult(userId: 'u1', token: 'tok');
  @override Future<AuthResult?> current() async => AuthResult(userId: 'u1', token: 'tok');
  @override Future<void> signOut() async {}
}

void main() {
  test('push 上传本地 photo 设 photoKey', () async {
    final repo = SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
    final oss = FakeCos();
    final remote = _FakeRemote();
    final engine = SyncEngine(repository: repo, remote: remote, auth: _FakeAuth(), cos: oss);
    await repo.save(Entry(id: 'e1', content: 'x', createdAt: DateTime.now(), updatedAt: DateTime.now(),
      dayKey: '2026-11-03', photo: Uint8List.fromList([1, 2, 3])));
    await engine.pushOnce();
    final all = await repo.exportAll();
    expect(all.single.photoKey, isNotNull);
    await repo.close(); await oss.close();
  });

  test('pull 下载远端 photoKey 的 BLOB', () async {
    final repo = SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
    final oss = FakeCos();
    // 先上传一份照片到 COS
    final key = await oss.upload(Uint8List.fromList([9, 9, 9]));
    final remote = _FakeRemote();
    remote.nextPull = SyncPullResponse(cursor: 1, entries: [
      SyncEntry(id: 'e2', createdAt: 1000, fields: const {'photo': FieldValue(null, 0), 'content': FieldValue('hi', 100)}),
    ]);
    // 注：上面 photo 字段 v=null 表示无照片；改成有 key 的：
    remote.nextPull = SyncPullResponse(cursor: 1, entries: [
      SyncEntry(id: 'e2', createdAt: 1000, fields: {'photo': FieldValue(key, 5000), 'content': FieldValue('hi', 100)}),
    ]);
    final engine = SyncEngine(repository: repo, remote: remote, auth: _FakeAuth(), cos: oss);
    await engine.pullOnce();
    final all = await repo.exportAll();
    final e = all.singleWhere((x) => x.id == 'e2');
    expect(e.photoKey, key);
    expect(e.photo, Uint8List.fromList([9, 9, 9])); // 下载了 BLOB
    await repo.close(); await oss.close();
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && ..\scripts\flutter.ps1 test test/data/sync/sync_engine_photo_test.dart`
Expected: FAIL —— SyncEngine 无 cos 参数 / photo 上传下载未实现。

- [ ] **Step 3: 写实现**

Modify `sync_engine.dart`：
- 构造函数加 `required CosGateway cos`。
- `pushOnce`：在构批次前，遍历 entries，对 `photo != null && photoKey == null` 的条目，`final key = await cos.upload(entry.photo!)`，构造新 Entry（photoKey=key, syncStamps['photo']=now/updatedAt），`repo.saveMerged(newEntry)`（保留 photo 戳）。然后用更新后的条目构批次。
- `pullOnce`：在 saveMerged 后，对 `photoKey != null && photo == null` 的条目，`final bytes = await cos.download(photoKey)`，构造新 Entry（photo=bytes），`repo.saveMerged(...)`。
- `_fromSyncEntry`：设 photoKey（从 fields['photo']?.v）。photo BLOB 在 pullOnce 后下载（不在 _fromSyncEntry，那是纯函数）。

> push 上传用 saveMerged（保留 photo 戳，避免 save 重算）。pull 下载用 saveMerged（photo 是本地缓存，不进 sync 字段，saveMerged 保留 photoKey 与 photo 戳）。

- [ ] **Step 4: 运行测试确认通过 + 既有回归**

Run: `cd client && ..\scripts\flutter.ps1 test`
Expected: 新测试通过 + 既有 417+ 项不回归。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/data/sync/sync_engine.dart client/test/data/sync/sync_engine_photo_test.dart
git commit -m "feat(F013):照片上传下载,add photo upload and download in sync engine"
```

---

## Task 4: UI 照片缩略图从 photoKey 下载

**Files:**
- Modify: `client/lib/src/ui/home_page.dart`（composer 照片缩略图：photo BLOB 为 null 但 photoKey 存在时下载显示）
- Test: `client/test/ui/home_page_photo_sync_test.dart`

**Interfaces:**
- Consumes: `SyncEngine.cos`、`Entry.photo`/`photoKey`。
- Produces: composer 照片缩略图支持「只有 photoKey 没有 BLOB」时下载显示。

- [ ] **Step 1: 写失败测试**

`client/test/ui/home_page_photo_sync_test.dart`：编辑一条带 photoKey 但 photo=null 的条目，composer 显示缩略图（下载 BLOB 后显示）。

> 参照既有 `home_page_photo_test.dart` 模式。测试替身 FakeCos 注入 SyncEngine。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && ..\scripts\flutter.ps1 test test/ui/home_page_photo_sync_test.dart`
Expected: FAIL —— 缩略图不显示（photo=null 时无图）。

- [ ] **Step 3: 写实现**

Modify `home_page.dart` composer 的照片缩略图：当前 `if (_editor.photo != null)` 显示缩略图。改为：若 `_editor.photo != null` 直接显示；若 `_editor.photo == null` 但 `_editor.photoKey != null`，用 `Image.memory` 前先 `cos.download(photoKey)` 下载 BLOB 显示（异步，加载中显示占位）。编辑器需暴露 photoKey（`EntryEditorController` 加 `photoKey` getter，编辑时随 Entry 带入）。

> 最小实现：composer 缩略图区在 photo==null && photoKey!=null 时，触发一次 cos.download 并 setState 显示。编辑器 `_saveLoop` 构造 Entry 时带 photoKey。

- [ ] **Step 4: 运行测试确认通过 + 既有回归**

Run: `cd client && ..\scripts\flutter.ps1 test`
Expected: 新测试通过 + 既有不回归。analyze 干净（除 pre-existing warning）。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/ui/home_page.dart client/lib/src/ui/entry_editor_controller.dart client/test/ui/home_page_photo_sync_test.dart
git commit -m "feat(F013):照片缩略图同步,add photo thumbnail from photoKey"
```

---

## 自检

- **Spec 覆盖**：spec 第 6 节（照片经服务端代理 COS、sha256 key）、第 4 节（同步字段）由 Task 1-4 覆盖。
- **占位符**：Task 3 测试里 `remote.nextPull` 先设 null photo 再改有 key 的——这是测试构造，非占位。
- **类型一致**：photoKey/photo/CosGateway/FakeCos 签名在实现与测试一致。

## 执行交接

本计划保存到 `docs/superpowers/plans/云同步-照片同步-photo-sync.md`。真机腾讯云 COS（服务端代理读写、私有 bucket）延后到 bucket 就绪。
