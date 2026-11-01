import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/stats_page.dart';

import '../support/memory_repository.dart';

void main() {
  Entry entry(String id, String dayKey) => Entry(
        id: id,
        content: '内容 $id',
        createdAt: DateTime.utc(2026, 10, 28, 8),
        updatedAt: DateTime.utc(2026, 10, 28, 8),
        dayKey: dayKey,
      );

  Future<MemoryRepository> seed(List<Entry> entries) async {
    final repo = MemoryRepository();
    for (final e in entries) {
      await repo.save(e);
    }
    return repo;
  }

  Future<void> showStats(WidgetTester tester, MemoryRepository repo) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 2000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StatsPage(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AC-01: 有数据 → 显示热力图网格', (tester) async {
    final repo = await seed([entry('a', '2026-10-28')]);
    await showStats(tester, repo);
    expect(find.text('记录热力图'), findsOneWidget);
    // 网格格子是带圆角的 Container，多条（含星期表头）。
    expect(find.byType(Container), findsWidgets);
  });

  testWidgets('AC-02: 某天多条 → 格子显示条数', (tester) async {
    final repo = await seed([
      entry('a', '2026-10-28'),
      entry('b', '2026-10-28'),
      entry('c', '2026-10-28'),
    ]);
    await showStats(tester, repo);
    // 当天写 3 条，格子里显示 "3"。
    expect(find.text('3'), findsWidgets);
  });

  testWidgets('AC-04: 无数据 → 空状态', (tester) async {
    final repo = await seed([]);
    await showStats(tester, repo);
    expect(find.text('还没有记录'), findsOneWidget);
    expect(find.text('写下第一条，开始看到你的记录节奏'), findsOneWidget);
  });

  testWidgets('AC-06: 非法 dayKey 跳过，不让网格崩', (tester) async {
    final repo = MemoryRepository();
    // 直接塞一条非法 dayKey 的脏数据。
    repo.entries['dirty'] = Entry(
      id: 'dirty',
      content: '脏数据',
      createdAt: DateTime.utc(2026, 10, 28, 8),
      updatedAt: DateTime.utc(2026, 10, 28, 8),
      dayKey: '2026',
    );
    await showStats(tester, repo);
    // 页面能打开，不崩溃。
    expect(tester.takeException(), isNull);
    expect(find.text('记录热力图'), findsOneWidget);
  });

  testWidgets('AC-05: 跨月数据 → 网格正常显示', (tester) async {
    final repo = await seed([
      entry('a', '2026-09-30'),
      entry('b', '2026-10-01'),
    ]);
    await showStats(tester, repo);
    expect(find.text('记录热力图'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
