import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';
import 'package:local_diary/src/ui/home_page.dart';
import 'package:sync_core/sync_core.dart';

import '../support/memory_repository.dart';

/// SyncEngine 依赖的最小远程替身：pull 永远返回空批次、push 空操作。
class _FakeRemote implements SyncRemote {
  @override
  Future<SyncPullResponse> pull(String t, int c) async =>
      SyncPullResponse(cursor: c, entries: []);

  @override
  Future<void> push(String t, SyncPushBatch b) async {}
}

/// SyncEngine 依赖的鉴权替身：current 永远返回已登录态。
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

/// 内存版 COS 替身：不用真实文件 I/O（widget 测试跑在 FakeAsync 上，
/// 真实文件的异步延续排不上空）。
class _InMemoryCos implements CosGateway {
  @override
  Future<String> upload(Uint8List bytes) async => 'key';

  @override
  Future<Uint8List> download(String key) async => Uint8List(0);

  @override
  Future<String> presign(String key) async => 'fake://$key';
}

/// 记录 triggerPush 调用的 SyncEngine 替身：只计数，不真正推送。
class _CountingSyncEngine extends SyncEngine {
  int pushes = 0;
  _CountingSyncEngine({
    required super.repository,
    required super.remote,
    required super.auth,
    required super.cos,
    required super.now,
  });

  @override
  void triggerPush({Duration debounce = const Duration(seconds: 30)}) {
    pushes++;
  }
}

void main() {
  testWidgets('T-34 退后台只落盘不发网络推送，回前台才补推', (tester) async {
    final repo = MemoryRepository();
    final engine = _CountingSyncEngine(
      repository: repo,
      remote: _FakeRemote(),
      auth: _FakeAuth(),
      cos: _InMemoryCos(),
      now: () => DateTime.now(),
    );
    await tester.pumpWidget(
      MaterialApp(home: HomePage(repository: repo, syncEngine: engine)),
    );
    await tester.pumpAndSettle();

    // 直接调 HomePage 的 didChangeAppLifecycleState（State 上是
    // @visibleForTesting）——不经框架的 handleAppLifecycleStateChanged：
    // 框架对生命周期迁移序列有断言（进入 resumed 前须为 inactive），
    // 而这里要测的正是 HomePage 自身在退后台/回前台时的行为。
    final state = tester.state(find.byType(HomePage)) as dynamic;

    // 退后台：不得发起网络推送（T-34）——Android 会挂起后台的 Dart isolate，
    // HTTP 请求的 await 迟迟不返回，推送会长时间挂起（日记同步不出去）。
    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(engine.pushes, 0, reason: '退后台时不得发起网络推送（T-34）');

    // 回前台：必须补推，把退后台期间落盘的条目送出去。
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(engine.pushes, greaterThan(0),
        reason: '回前台必须补推退后台期间落盘的条目（T-34）');

    engine.stop();
  });
}
