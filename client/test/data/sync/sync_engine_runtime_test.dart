import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';
import 'package:local_diary/src/data/sync/fake_cos.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sync_core/sync_core.dart';

class _FakeRemote implements SyncRemote {
  SyncPullResponse? nextPull;
  final List<SyncPushBatch> pushes = [];
  /// pull 抛错次数：前 N 次抛 [pullError]，之后返回空响应。
  int failCount = 0;
  Object? pullError;
  int pullCalls = 0;
  /// push 注入异常：非 null 时 push 抛出。
  Object? pushError;
  @override
  Future<SyncPullResponse> pull(String t, int c) async {
    pullCalls++;
    if (pullCalls <= failCount) {
      final e = pullError;
      if (e != null) throw e;
    }
    return nextPull ?? SyncPullResponse(cursor: c, entries: []);
  }
  @override
  Future<void> push(String t, SyncPushBatch b) async {
    pushes.add(b);
    final e = pushError;
    if (e != null) throw e;
  }
}

/// 未登录替身：current() 返回 null。
class _LoggedOutAuth implements AuthProvider {
  @override
  Future<AuthResult> register(String e, String p) async =>
      throw UnimplementedError();

  @override
  Future<AuthResult> login(String e, String p) async =>
      throw UnimplementedError();

  @override
  Future<AuthResult?> current() async => null;

  @override
  Future<void> signOut() async {}
}

class _FakeAuth implements AuthProvider {
  @override
  Future<AuthResult> register(String e, String p) async =>
      throw UnimplementedError();

  @override
  Future<AuthResult> login(String e, String p) async =>
      AuthResult(userId: 'u1', token: 'tok');

  @override
  Future<AuthResult?> current() async =>
      AuthResult(userId: 'u1', token: 'tok');

  @override
  Future<void> signOut() async {}
}

/// 等待 state 变为目标状态，超时抛错。
Future<void> _waitFor(
    SyncEngine engine, SyncState target, {int timeoutMs = 5000}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (DateTime.now().isBefore(deadline)) {
    if (engine.state == target) return;
    await Future.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('timed out waiting for $target; current=${engine.state}');
}

void main() {
  setUpAll(sqfliteFfiInit);

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
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final remote = _FakeRemote(); // pull 返回空，立即成功
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        cos: FakeCos(),
        now: () => DateTime.now(),
      );
      expect(engine.state, SyncState.idle);

      final states = <SyncState>[];
      final sub = engine.stateChanged.listen((s) => states.add(s));

      engine.start();
      await _waitFor(engine, SyncState.synced);

      expect(states.first, SyncState.syncing);
      expect(states.last, SyncState.synced);
      expect(states.indexOf(SyncState.syncing),
          0, reason: '首个状态事件必须是 syncing');
      expect(states.indexOf(SyncState.synced),
          states.length - 1, reason: '最后一个状态事件必须是 synced');

      await sub.cancel();
      engine.stop();
      await repo.close();
    });

    test('pull 抛非网络异常不重试，直接 failed', () async {
      // 401/格式错误等非 SocketException：_pullWithRetry 不捕获、不重试，
      // 由 triggerPull 捕获置 failed。此用例同时验证「不重试」——pullCalls==1。
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final remote = _FakeRemote();
      remote.failCount = 1;
      remote.pullError = ArgumentError('bad format');
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        cos: FakeCos(),
        now: () => DateTime.now(),
      );
      final sub = engine.stateChanged.listen((_) {});
      engine.start();
      await _waitFor(engine, SyncState.failed);
      expect(remote.pullCalls, 1,
          reason: '非网络异常不应触发退避重试，只调一次 pull');
      await sub.cancel();
      engine.stop();
      await repo.close();
    });

    test('start 重复调用不重复启动', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final remote = _FakeRemote();
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        cos: FakeCos(),
        now: () => DateTime.now(),
      );
      engine.start();
      engine.start(); // 第二次应被忽略
      await _waitFor(engine, SyncState.synced);
      expect(remote.pullCalls, 1,
          reason: 'start 期间已有 pull 在跑，重复 start 不应并发触发');
      engine.stop();
      await repo.close();
    });

    test('stop 后 stateChanged 关闭', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final remote = _FakeRemote();
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        cos: FakeCos(),
        now: () => DateTime.now(),
      );
      engine.start();
      await _waitFor(engine, SyncState.synced);
      // 先监听再 stop：close() 会向现有监听者发送 done（或 closed 错误）。
      final done = Completer<void>();
      final sub = engine.stateChanged.listen((_) {},
          onDone: done.complete, onError: (_) => done.complete());
      engine.stop();
      await expectLater(done.future, completes);
      await sub.cancel();
      await repo.close();
    });
  });

  group('triggerPush', () {
    test('triggerPush 安排 30s 防抖推送', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final remote = _FakeRemote();
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        cos: FakeCos(),
        now: () => DateTime.now(),
      );
      await repo.save(Entry(
        id: 'e1',
        content: 'hi',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dayKey: '2026-11-04',
      ));
      // 防抖窗口内多次调用只安排一次 30s 定时；此处仅验证不抛错且不立即推送。
      engine.triggerPush();
      expect(remote.pushes, isEmpty, reason: '防抖窗口内不应立即推送');
      engine.stop();
      await repo.close();
    });

    test('T-09 push 失败置 failed（不静默）', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final remote = _FakeRemote();
      remote.pushError = StateError('push boom');
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        cos: FakeCos(),
        now: () => DateTime.now(),
      );
      await repo.save(Entry(
        id: 'e1',
        content: 'hi',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dayKey: '2026-11-04',
      ));
      // 短防抖（测试不等 30 秒）；登录态预检 + 定时器回调都在真实异步下执行。
      engine.triggerPush(debounce: const Duration(milliseconds: 10));
      await Future.delayed(const Duration(milliseconds: 500));
      expect(engine.state, SyncState.failed,
          reason: '推送失败后状态必须置 failed，不得停留在 synced');
      engine.stop();
      await repo.close();
    });

    test('T-10 stop 后 start 重建状态流（不死流）', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final remote = _FakeRemote();
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        cos: FakeCos(),
        now: () => DateTime.now(),
      );
      engine.start();
      await _waitFor(engine, SyncState.synced);
      engine.stop();
      engine.start();
      await _waitFor(engine, SyncState.synced); // start 触发的 pull 完成
      // 重建后的流必须能继续广播状态（监听在流重建后注册）。
      final seen = <SyncState>[];
      engine.stateChanged.listen((s) => seen.add(s));
      await engine.triggerPull(); // 触发一次状态迁移
      expect(seen, contains(SyncState.syncing),
          reason: 'start 重建的流必须能广播新状态');
      engine.stop();
      await repo.close();
    });

    test('T-11 未登录 triggerPush 不安排推送', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final remote = _FakeRemote();
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _LoggedOutAuth(),
        cos: FakeCos(),
        now: () => DateTime.now(),
      );
      engine.triggerPush();
      // 登录态预检是异步的——等待其完成。
      await Future.delayed(const Duration(milliseconds: 100));
      expect(remote.pushes, isEmpty,
          reason: '未登录时不应安排推送（登出后不浪费一次推送循环）');
      engine.stop();
      await repo.close();
    });
  });
}
