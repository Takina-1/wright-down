import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';
import 'package:local_diary/src/data/sync/fake_cos.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/sync/login_page.dart';
import 'package:sync_core/sync_core.dart';

import '../../support/memory_repository.dart';

/// 可配置的鉴权替身：login/register 成功或抛错，并记录调用次数。
class _FakeAuth implements AuthProvider {
  bool loginShouldFail = false;
  bool registerShouldFail = false;
  int loginCalls = 0;
  int registerCalls = 0;

  @override
  Future<AuthResult> register(String e, String p) async {
    registerCalls++;
    if (registerShouldFail) throw StateError('register failed');
    return const AuthResult(userId: 'u1', token: 'tok');
  }

  @override
  Future<AuthResult> login(String e, String p) async {
    loginCalls++;
    if (loginShouldFail) throw StateError('invalid email or password');
    return const AuthResult(userId: 'u1', token: 'tok');
  }

  @override
  Future<AuthResult?> current() async => null;

  @override
  Future<void> signOut() async {}
}

/// 记录 triggerPush 调用的 SyncEngine 替身：只计数，不真正推送。
class _FakeSyncEngine extends SyncEngine {
  int pushes = 0;

  _FakeSyncEngine()
    : super(
        repository: MemoryRepository(),
        remote: _NoopRemote(),
        auth: _FakeAuth(),
        oss: FakeCos(),
        now: () => DateTime.now(),
      );

  @override
  void triggerPush() {
    pushes++;
  }
}

class _NoopRemote implements SyncRemote {
  @override
  Future<SyncPullResponse> pull(String token, int cursor) async =>
      SyncPullResponse(cursor: cursor, entries: const []);

  @override
  Future<void> push(String token, SyncPushBatch batch) async {}
}

final _time = DateTime.utc(2026, 10, 28, 8);
Entry _entry(String id, String content) => Entry(
  id: id,
  content: content,
  createdAt: _time,
  updatedAt: _time,
  dayKey: '2026-10-28',
);

Future<void> _enterCredentials(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login-email')), 'user@example.com');
  await tester.enterText(find.byKey(const Key('login-password')), 'password');
}

void main() {
  testWidgets('登录成功且本机有条目时弹出认领对话框', (tester) async {
    final repo = MemoryRepository()..entries['a'] = _entry('a', '第一条');
    final auth = _FakeAuth();
    final engine = _FakeSyncEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginPage(auth: auth, syncEngine: engine, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _enterCredentials(tester);
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(find.text('要把本机 1 条日记同步到云端吗？'), findsOneWidget);
    expect(engine.pushes, 0); // 还没点「是」
  });

  testWidgets('认领点是触发推送', (tester) async {
    final repo = MemoryRepository()..entries['a'] = _entry('a', '第一条');
    final auth = _FakeAuth();
    final engine = _FakeSyncEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginPage(auth: auth, syncEngine: engine, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _enterCredentials(tester);
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('是'));
    await tester.pumpAndSettle();

    expect(engine.pushes, 1);
  });

  testWidgets('认领点否不触发推送', (tester) async {
    final repo = MemoryRepository()..entries['a'] = _entry('a', '第一条');
    final auth = _FakeAuth();
    final engine = _FakeSyncEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginPage(auth: auth, syncEngine: engine, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _enterCredentials(tester);
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('否'));
    await tester.pumpAndSettle();

    expect(engine.pushes, 0);
  });

  testWidgets('登录成功且本机无条目时不弹认领', (tester) async {
    final repo = MemoryRepository(); // 空
    final auth = _FakeAuth();
    final engine = _FakeSyncEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginPage(auth: auth, syncEngine: engine, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _enterCredentials(tester);
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(auth.loginCalls, 1);
    expect(find.textContaining('要把本机'), findsNothing);
    expect(engine.pushes, 0);
  });

  testWidgets('登录失败显示错误且不弹认领', (tester) async {
    final repo = MemoryRepository()..entries['a'] = _entry('a', '第一条');
    final auth = _FakeAuth()..loginShouldFail = true;
    final engine = _FakeSyncEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginPage(auth: auth, syncEngine: engine, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _enterCredentials(tester);
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(find.text('登录失败，请重试'), findsOneWidget);
    expect(find.textContaining('要把本机'), findsNothing);
    expect(engine.pushes, 0);
  });

  testWidgets('注册成功且本机有条目时弹出认领对话框', (tester) async {
    final repo = MemoryRepository()..entries['a'] = _entry('a', '第一条');
    final auth = _FakeAuth();
    final engine = _FakeSyncEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginPage(auth: auth, syncEngine: engine, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _enterCredentials(tester);
    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();

    expect(auth.registerCalls, 1);
    expect(find.text('要把本机 1 条日记同步到云端吗？'), findsOneWidget);
  });

  testWidgets('注册失败显示错误', (tester) async {
    final repo = MemoryRepository();
    final auth = _FakeAuth()..registerShouldFail = true;
    final engine = _FakeSyncEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginPage(auth: auth, syncEngine: engine, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _enterCredentials(tester);
    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();

    expect(find.text('注册失败，请重试'), findsOneWidget);
    expect(auth.registerCalls, 1);
  });
}
