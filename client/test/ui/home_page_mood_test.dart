import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/ui/home_page.dart';

import '../support/memory_repository.dart';

Future<void> _pumpHome(WidgetTester tester, MemoryRepository repo) async {
  await tester.pumpWidget(
    MaterialApp(home: HomePage(repository: repo)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('未设心情时入口显示 😊 占位', (tester) async {
    await _pumpHome(tester, MemoryRepository());
    expect(find.byKey(const Key('mood-entry')), findsOneWidget);
    expect(find.text('😊'), findsWidgets);
  });

  testWidgets('点开弹层列出 5 种心情与文字', (tester) async {
    final repo = MemoryRepository();
    await _pumpHome(tester, repo);
    await tester.tap(find.byKey(const Key('mood-entry')));
    await tester.pumpAndSettle();
    for (final label in ['开心', '不错', '一般', '平淡', '难过']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('清除'), findsNothing); // 未设时无清除
  });

  testWidgets('选择心情后入口显示对应 emoji 并落库', (tester) async {
    final repo = MemoryRepository();
    await _pumpHome(tester, repo);
    // 心情随正文一起落库（F006 计划 Task 6 注：空正文条目不落库，
    // 测试用非空正文验证 mood 落库）。
    await tester.enterText(find.byKey(const Key('entry-content')), '今天开心');
    await tester.tap(find.byKey(const Key('mood-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开心'));
    await tester.pumpAndSettle();
    expect(find.text('😄'), findsWidgets);
    await tester.pump(const Duration(seconds: 2)); // 等防抖保存
    expect(repo.entries.values.single.mood, 'happy');
  });

  testWidgets('已设心情后弹层显示清除，清除后恢复未设', (tester) async {
    final repo = MemoryRepository();
    await _pumpHome(tester, repo);
    await tester.tap(find.byKey(const Key('mood-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开心'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mood-entry')));
    await tester.pumpAndSettle();
    expect(find.text('清除'), findsOneWidget);
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(find.text('😊'), findsWidgets);
  });
}
