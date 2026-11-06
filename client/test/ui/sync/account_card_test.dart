import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/ui/local_data_page.dart';
import 'package:local_diary/src/ui/sync/account_card.dart';
import 'package:local_diary/src/ui/sync/login_page.dart';
import 'package:sync_core/sync_core.dart';

import '../../support/memory_repository.dart';

/// 可配置的鉴权替身：current() 返回预设结果，signOut 把它清空并记录调用。
class _FakeAuth implements AuthProvider {
  AuthResult? currentResult;
  bool signedOut = false;

  @override
  Future<AuthResult> register(String e, String p) async =>
      AuthResult(userId: 'u1', token: 'tok');
  @override
  Future<AuthResult> login(String e, String p) async =>
      AuthResult(userId: 'u1', token: 'tok');
  @override
  Future<AuthResult?> current() async => currentResult;
  @override
  Future<void> signOut() async {
    signedOut = true;
    currentResult = null;
  }
}

void main() {
  testWidgets('未登录显示登录按钮', (tester) async {
    final auth = _FakeAuth(); // current() -> null
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AccountCard(auth: auth))),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('登出'), findsNothing);
  });

  testWidgets('已登录显示账号与登出', (tester) async {
    final auth = _FakeAuth()
      ..currentResult = const AuthResult(userId: 'u1', token: 'tok');
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AccountCard(auth: auth))),
    );
    await tester.pumpAndSettle();

    // 账号标识（AuthResult 只带 userId，没有 email，故显示 userId）。
    expect(find.text('u1'), findsOneWidget);
    expect(find.text('登出'), findsOneWidget);
    expect(find.text('登录'), findsNothing);
  });

  testWidgets('登出调用 signOut 并回到未登录', (tester) async {
    final auth = _FakeAuth()
      ..currentResult = const AuthResult(userId: 'u1', token: 'tok');
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AccountCard(auth: auth))),
    );
    await tester.pumpAndSettle();

    expect(find.text('登出'), findsOneWidget);
    await tester.tap(find.text('登出'));
    await tester.pumpAndSettle();

    expect(auth.signedOut, isTrue);
    // signOut 把 current() 清空后，卡片刷新回未登录态。
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('登出'), findsNothing);
  });

  testWidgets('未登录点登录进入登录页', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AccountCard(auth: auth))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('LocalDataPage 传入 auth 时顶部嵌入账号卡', (tester) async {
    final auth = _FakeAuth(); // 未登录
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDataPage(repository: MemoryRepository(), auth: auth),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AccountCard), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    // 账号卡不影响既有的 ListTile 入口顺序。
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles, ['统计', '导出与备份', '回收站', '本地数据说明']);
  });

  testWidgets('LocalDataPage 未传 auth 时不显示账号卡', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDataPage(repository: MemoryRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AccountCard), findsNothing);
  });
}
