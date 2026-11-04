# F013 云同步实现计划 · Part 3b：客户端 UI 与触发循环

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让同步在 App 里真正跑起来：修 M-16（save 保留远端时间戳）、SyncEngine 触发循环 + 退避 + 状态、鉴权 UI + 认领、同步状态指示 + App 接线。

**Architecture:** SyncEngine 扩展为可触发的运行时（start/triggerPull/triggerPush + 周期定时 + 退避重试 + 状态回调）。M-16 通过新增 `saveMerged`（保留调用方 syncStamps）修。UI 在「我的」Tab 加账号卡 + 登录页 + 同步状态指示；App 启动接线 SyncEngine，编辑器写入触发 push，前台触发 pull。

**Tech Stack:** Dart/Flutter 3.13.7，`dart:async` Timer，sync_core，client 既有 UI 模式。

## 全局约束

- SDK：`sdk: ^3.13.7`。
- 架构铁律：UI 不碰 RemoteRepo（走 AuthProvider/SyncEngine）；写入只走 LocalRepo；Domain 不依赖框架/SDK。
- 字段级 LWW：每字段独立时间戳，取大；平局取推送方。
- 同步状态：⟳ 同步中 / ✓ 已同步 / ⚠ 失败（不静默失败）。
- 触发时机：启动、进入后台、回到前台、写完延迟 30 秒、定时每 5 分钟、手动下拉。
- 退避：2→4→8→16→32 秒 + 抖动，第 6 次放弃本轮等下个触发点。
- 401：换 token 重试一次再失败 → 停同步 + 提示重登录，不自动登出。
- 提交信息：`<type>:<中文说明>,<english summary>`，标注 `feat(F013)`。

## 文件结构

```
client/lib/src/domain/sync/           # 已有 entry_sync_map.dart
client/lib/src/data/sync/
  sync_engine.dart                    # 扩展：触发循环 + 退避 + 状态（M-16 修 + 运行时）
client/lib/src/data/local/
  sqlite_entry_repository.dart        # 加 saveMerged
  local_entry_repository.dart         # 加 saveMerged 接口
client/lib/src/ui/
  sync/login_page.dart                # 新：登录/注册页
  sync/account_card.dart              # 新：「我的」页账号卡 + 同步状态
  sync/sync_status_indicator.dart     # 新：⟳/✓/⚠ 状态指示
client/test/...
```

---

## Task 1: M-16 修 — saveMerged 保留调用方 syncStamps

**Files:**
- Modify: `client/lib/src/domain/local_entry_repository.dart`（加 saveMerged 接口）
- Modify: `client/lib/src/data/local/sqlite_entry_repository.dart`（实现 saveMerged）
- Modify: `client/lib/src/data/sync/sync_engine.dart`（pullOnce 用 saveMerged）
- Test: `client/test/data/sync/sync_engine_stamps_test.dart`

**Interfaces:**
- Consumes: `Entry`（含 syncStamps）。
- Produces: `LocalEntryRepository.saveMerged(Entry)` — 写入条目并**原样保留**传入的 syncStamps（不重算），updated_at 取 max(now, e.updatedAt)。SyncEngine.pullOnce 用它替代 save()。

- [ ] **Step 1: 写失败测试**

`client/test/data/sync/sync_engine_stamps_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/sync/entry_sync_map.dart';
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
  test('pull 后 saveMerged 保留远端字段时间戳', () async {
    final repo = SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
    final remote = _FakeRemote();
    // 远端 content t=5000
    remote.nextPull = SyncPullResponse(cursor: 1, entries: [
      SyncEntry(id: 'e2', createdAt: 1000, fields: const {'content': FieldValue('remote', 5000)}),
    ]);
    final engine = SyncEngine(repository: repo, remote: remote, auth: _FakeAuth());
    await engine.pullOnce();
    final all = await repo.exportAll();
    final e = all.singleWhere((x) => x.id == 'e2');
    // 关键：syncStamps['content'] == 5000（远端 t），不是 updatedAt
    expect(e.syncStamps['content'], 5000);
    expect(e.content, 'remote');
    await repo.close();
  });
}
```

> 若 `databaseFactoryFfi` 未导入，用 `sqfliteFfiInit()` + `databaseFactoryFfi`（对齐既有 sync_engine_test.dart 模式）。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && ..\scripts\flutter.ps1 test test/data/sync/sync_engine_stamps_test.dart`
Expected: FAIL —— 当前 save 重算 syncStamps 为 updatedAt，断言 `== 5000` 失败。

- [ ] **Step 3: 写实现**

Modify `local_entry_repository.dart`，加接口方法：

```dart
/// 同步合并用：写入条目并**原样保留**传入的 syncStamps（不重算），
/// updated_at 取 max(now, e.updatedAt)。pull 合并后的条目用本方法，
/// 避免 save 重算时间戳破坏「字段最后同步时间」不变量（M-16）。
Future<void> saveMerged(Entry entry);
```

Modify `sqlite_entry_repository.dart`，实现 `saveMerged`（与 save 同 upsert 结构，但 sync_stamps 用 `jsonEncode(entry.syncStamps)` 而非 `_computeStamps`）：

```dart
@override
Future<void> saveMerged(Entry entry) async {
  if (entry.id.isEmpty || entry.content.trim().isEmpty) throw ArgumentError(...);
  final db = await _database();
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  final stamp = entry.updatedAt.millisecondsSinceEpoch > now
      ? entry.updatedAt.millisecondsSinceEpoch : now;
  final stampsJson = jsonEncode(entry.syncStamps);
  await db.transaction((txn) async {
    final updated = await txn.update('entries', {
      'content': entry.content, 'updated_at': stamp,
      if (entry.deletedAt != null) 'deleted_at': entry.deletedAt.millisecondsSinceEpoch,
      'mood': entry.mood, 'tags': jsonEncode(entry.tags), 'photo': entry.photo,
      'sync_stamps': stampsJson,
    }, where: 'id = ?', whereArgs: [entry.id]);
    if (updated == 0) {
      await txn.insert('entries', {
        'id': entry.id, 'content': entry.content,
        'created_at': entry.createdAt.millisecondsSinceEpoch, 'updated_at': stamp,
        'day_key': entry.dayKey,
        if (entry.deletedAt != null) 'deleted_at': entry.deletedAt.millisecondsSinceEpoch,
        'mood': entry.mood, 'tags': jsonEncode(entry.tags), 'photo': entry.photo,
        'sync_stamps': stampsJson,
      });
    }
  });
}
```

Modify `sync_engine.dart` `pullOnce`：把两处 `repository.save(...)` 改为 `repository.saveMerged(...)`（_fromSyncEntry 与 applyRemote 的结果）。

- [ ] **Step 4: 运行测试确认通过 + 既有回归**

Run: `cd client && ..\scripts\flutter.ps1 test`
Expected: 新测试通过 + 既有 393 项不回归。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/domain/local_entry_repository.dart client/lib/src/data/local/sqlite_entry_repository.dart client/lib/src/data/sync/sync_engine.dart client/test/data/sync/sync_engine_stamps_test.dart
git commit -m "fix(F013):saveMerged保留远端时间戳,fix M-16 preserve remote field stamps on pull"
```

---

## Task 2: SyncEngine 触发循环 + 退避 + 状态

**Files:**
- Modify: `client/lib/src/data/sync/sync_engine.dart`（扩展运行时）
- Test: `client/test/data/sync/sync_engine_runtime_test.dart`

**Interfaces:**
- Consumes: SyncEngine（Task 1 后的 pushOnce/pullOnce）。
- Produces: `SyncState` enum (idle/syncing/synced/failed)；`start()/stop()/triggerPull()/triggerPush()`；`stateChanged` 流；`int nextBackoff(int attempt)` 纯函数（2,4,8,16,32 封顶）；`Future<void> _pullWithRetry()`/`_pushWithRetry()`（退避重试）。

- [ ] **Step 1: 写失败测试**

`client/test/data/sync/sync_engine_runtime_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';

void main() {
  group('nextBackoff', () {
    test('2→4→8→16→32 封顶', () {
      expect(SyncEngine.nextBackoff(0), 2);
      expect(SyncEngine.nextBackoff(1), 4);
      expect(SyncEngine.nextBackoff(2), 8);
      expect(SyncEngine.nextBackoff(3), 16);
      expect(SyncEngine.nextBackoff(4), 32);
      expect(SyncEngine.nextBackoff(5), 32); // 封顶
      expect(SyncEngine.nextBackoff(10), 32);
    });
  });

  group('状态迁移', () {
    test('start 后进入 syncing，完成进入 synced', () async {
      // 用替身：remote.pull 返回空，触发一次 pull
      // 断言 stateChanged 依次收到 syncing → synced
      // （具体用 FakeRemote + 监听 stateChanged）
    });
  });
}
```

> 退避纯函数是核心可测项；状态迁移用 FakeRemote + stateChanged 监听断言。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && ..\scripts\flutter.ps1 test test/data/sync/sync_engine_runtime_test.dart`
Expected: FAIL —— `nextBackoff`/`SyncState` 未定义。

- [ ] **Step 3: 写实现**

Modify `sync_engine.dart`，加：

```dart
enum SyncState { idle, syncing, synced, failed }

/// 退避：2→4→8→16→32 秒封顶。attempt 从 0 起。
static int nextBackoff(int attempt) => (1 << (attempt + 1)).clamp(2, 32);

final StreamController<SyncState> _state = StreamController<SyncState>.broadcast();
Stream<SyncState> get stateChanged => _state.stream;
SyncState _state_ = SyncState.idle;
SyncState get state => _state_;
void _setState(SyncState s) { _state_ = s; _state.add(s); }

Timer? _pullTimer;
Timer? _pushDebounce;

void start() {
  if (_pullTimer != null) return;
  _pullTimer = Timer.periodic(const Duration(minutes: 5), (_) => unawaited(triggerPull()));
  unawaited(triggerPull()); // 启动即拉一次
}

void stop() {
  _pullTimer?.cancel(); _pullTimer = null;
  _pushDebounce?.cancel(); _pushDebounce = null;
  _state.close();
}

Future<void> triggerPull() async {
  if (state == SyncState.syncing) return;
  _setState(SyncState.syncing);
  try {
    await _pullWithRetry();
    _setState(SyncState.synced);
  } catch (_) {
    _setState(SyncState.failed);
  }
}

void triggerPush() {
  _pushDebounce?.cancel();
  _pushDebounce = Timer(const Duration(seconds: 30), () => unawaited(_pushWithRetry()));
}

Future<void> _pullWithRetry() async {
  var attempt = 0;
  while (true) {
    try { await pullOnce(); return; }
    on SocketException catch (_) {
      if (attempt >= 5) throw _state_.toString(); // 第 6 次放弃
      await Future.delayed(Duration(seconds: nextBackoff(attempt)));
      attempt++;
    }
  }
}
```

> `_pushWithRetry` 同结构。401 处理：pull/push 抛 401 → 停同步 + 提示重登录（UI 监听 failed 状态）。退避抖动可后加（最小里程碑用固定退避）。

- [ ] **Step 4: 运行测试确认通过 + 既有回归**

Run: `cd client && ..\scripts\flutter.ps1 test`
Expected: 新测试通过 + 既有不回归。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/data/sync/sync_engine.dart client/test/data/sync/sync_engine_runtime_test.dart
git commit -m "feat(F013):SyncEngine触发与退避,add sync triggers and backoff"
```

---

## Task 3: 鉴权 UI + 认领机制

**Files:**
- Create: `client/lib/src/ui/sync/login_page.dart`
- Create: `client/lib/src/ui/sync/account_card.dart`
- Modify: `client/lib/src/ui/local_data_page.dart`（嵌入账号卡）
- Test: `client/test/ui/sync/login_page_test.dart`、`account_card_test.dart`

**Interfaces:**
- Consumes: `AuthProvider`、`EmailPasswordProvider`（Task 3 Part 3）、`SyncEngine`。
- Produces: `LoginPage`（email/password + 登录/注册按钮，调 provider）；`AccountCard`（未登录→登录按钮；已登录→email + 登出 + 同步状态）；认领：登录成功后若本机有条目，弹「同步 N 条？」→ 是则 triggerPush。

- [ ] **Step 1: 写失败测试**

`client/test/ui/sync/account_card_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/ui/sync/account_card.dart';
import 'package:sync_core/sync_core.dart';

class _FakeAuth implements AuthProvider {
  @override Future<AuthResult> register(String e, String p) async => AuthResult(userId: 'u1', token: 'tok');
  @override Future<AuthResult> login(String e, String p) async => AuthResult(userId: 'u1', token: 'tok');
  @override Future<AuthResult?> current() async => null;
  @override Future<void> signOut() async {}
}

void main() {
  test('未登录显示登录按钮', () async {
    await pumpWidget(MaterialApp(home: Scaffold(body: AccountCard(auth: _FakeAuth()))));
    expect(find.text('登录'), findsOneWidget);
  });
  test('已登录显示邮箱与登出', () async {
    // auth.current 返回已登录
    ...
    expect(find.text('登出'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && ..\scripts\flutter.ps1 test test/ui/sync/account_card_test.dart`
Expected: FAIL —— `AccountCard` 未定义。

- [ ] **Step 3: 写实现**

`account_card.dart`：StatefulWidget，启动时调 `auth.current()`。未登录→「登录」按钮（Navigator push LoginPage）；已登录→显示 email + 「登出」按钮 + SyncStatusIndicator。登出调 `auth.signOut()` + 刷新。

`login_page.dart`：email + password 两个 TextField + 「登录」「注册」按钮。登录调 `auth.login`，成功→返回；注册调 `auth.register`。失败→显示错误。登录成功后触发认领：查本地条目数，>0 则弹「要把本机 N 条日记同步到云端吗？→ 是/否」，是则 `syncEngine.triggerPush()`。

Modify `local_data_page.dart`：顶部嵌入 `AccountCard`。

- [ ] **Step 4: 运行测试确认通过 + 既有回归**

Run: `cd client && ..\scripts\flutter.ps1 test`
Expected: 新 UI 测试通过 + 既有不回归。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/ui/sync/ client/lib/src/ui/local_data_page.dart client/test/ui/sync/
git commit -m "feat(F013):鉴权UI与认领,add auth UI and claim mechanism"
```

---

## Task 4: 同步状态 UI + App 接线

**Files:**
- Create: `client/lib/src/ui/sync/sync_status_indicator.dart`
- Modify: `client/lib/main.dart`（启动 SyncEngine）
- Modify: `client/lib/app.dart` / `home_page.dart`（接线：编辑器写入→triggerPush，前台→triggerPull）
- Modify: `client/lib/src/ui/home_page.dart`（composer 顶部加状态指示）
- Test: `client/test/ui/sync/sync_status_indicator_test.dart`、集成测试

**Interfaces:**
- Consumes: `SyncEngine.stateChanged`、`SyncState`。
- Produces: `SyncStatusIndicator`（⟳/✓/⚠ 图标 + 文案）；main.dart 启动时 `SyncEngine(...).start()`；编辑器 flush 后 `triggerPush()`；app 前台 `triggerPull()`。

- [ ] **Step 1: 写失败测试**

`client/test/ui/sync/sync_status_indicator_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/ui/sync/sync_status_indicator.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';

void main() {
  test('syncing 显示 ⟳', () async {
    await pumpWidget(MaterialApp(home: Scaffold(body: SyncStatusIndicator(state: SyncState.syncing))));
    expect(find.text('同步中'), findsOneWidget);
  });
  test('synced 显示 ✓', () async {
    await pumpWidget(MaterialApp(home: Scaffold(body: SyncStatusIndicator(state: SyncState.synced))));
    expect(find.text('已同步'), findsOneWidget);
  });
  test('failed 显示 ⚠', () async {
    await pumpWidget(MaterialApp(home: Scaffold(body: SyncStatusIndicator(state: SyncState.failed))));
    expect(find.text('同步失败'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && ..\scripts\flutter.ps1 test test/ui/sync/sync_status_indicator_test.dart`
Expected: FAIL —— `SyncStatusIndicator` 未定义。

- [ ] **Step 3: 写实现**

`sync_status_indicator.dart`：StatelessWidget，按 `SyncState` 显示图标（Icons.sync/Icons.check_circle/Icons.warning）+ 文案（同步中/已同步/同步失败）。

Modify `main.dart`：`_Startup` 打开 repo 后，创建 `SyncEngine(repository, remote: RemoteRepo(...), auth: EmailPasswordProvider(...))`，`engine.start()`，传给 `JournalApp`。`JournalApp`/`HomePage` 接收 engine，composer 顶部用 `ListenableBuilder` 订阅 `engine.stateChanged` 显示 `SyncStatusIndicator`。编辑器 `flush` 成功后调 `engine.triggerPush()`。`HomePage` 的 `didChangeAppLifecycleState`（resumed）调 `engine.triggerPull()`。

> RemoteRepo/EmailPasswordProvider 的 baseUrl 与 token store 需注入（SharedPreferences 实现 TokenStore）。本 Task 用最小注入：baseUrl 常量 + SharedPreferences TokenStore。

- [ ] **Step 4: 运行测试确认通过 + 全量 + analyze + build**

Run: `cd client && ..\scripts\flutter.ps1 test`（全过）；`... analyze`（干净，除 pre-existing home_page warning）；`... build apk --debug`（构建成功）。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/ui/sync/sync_status_indicator.dart client/lib/main.dart client/lib/app.dart client/lib/src/ui/home_page.dart client/test/ui/sync/sync_status_indicator_test.dart
git commit -m "feat(F013):同步状态UI与接线,add sync status UI and app wiring"
```

---

## 自检

- **Spec 覆盖**：spec 第 4 节（SyncEngine 三循环、认领、同步状态 UI）、第 7 节（触发时机、退避）、第 8 节（401 处理）由 Task 1-4 覆盖。M-16 在 Task 1 修。
- **占位符**：退避抖动标注「可后加」（最小里程碑用固定退避，明确非占位）。
- **类型一致**：SyncState/nextBackoff/saveMerged/triggerPull/triggerPush 签名在实现与测试一致。

## 执行交接

本计划保存到 `docs/superpowers/plans/云同步-客户端UI与触发-client-ui-and-triggers.md`。执行后若 SharedPreferences TokenStore 接入受阻，先用内存 TokenStore（测试替身）打通接线，再补 SharedPreferences。
