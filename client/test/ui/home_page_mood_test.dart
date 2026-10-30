import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
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

  testWidgets('AC-06: 编辑已设心情的条目，弹层显示当前心情为已选', (tester) async {
    final repo = MemoryRepository();
    // Pre-populate with an entry that has mood='happy'
    repo.entries['e1'] = Entry(
      id: 'e1',
      content: '今天很开心',
      createdAt: DateTime(2026, 10, 30, 2, 0),
      updatedAt: DateTime(2026, 10, 30, 2, 0),
      dayKey: '2026-10-30',
      mood: 'happy',
    );
    await _pumpHome(tester, repo);
    // Switch to review tab
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    // Click on the entry in the timeline to trigger edit
    await tester.tap(find.text('今天很开心'));
    await tester.pumpAndSettle();
    // Now we should be back on the composer tab with the entry loaded
    // Open the mood sheet
    await tester.tap(find.byKey(const Key('mood-entry')));
    await tester.pumpAndSettle();
    // AC-06: The '开心' ListTile should have a check icon (selected state)
    final happyTile = find.ancestor(
      of: find.text('开心'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: happyTile, matching: find.byIcon(Icons.check)),
      findsOneWidget,
      reason: 'AC-06: 已设心情的条目弹层应显示当前心情为已选',
    );
  });
}
