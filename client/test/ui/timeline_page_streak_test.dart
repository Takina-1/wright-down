import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/timeline_page.dart';

import '../support/memory_repository.dart';

/// 连续天数卡片的组件测试。
///
/// `today` 通过 [TimelinePage.today] 注入以固定「今天」，避免午夜抖动；
/// 条目 `dayKey` 用 naive 本地日，与卡片口径一致。
void main() {
  final today = DateTime(2026, 10, 31);

  Future<MemoryRepository> seed(List<Entry> entries) async {
    final repo = MemoryRepository();
    for (final e in entries) {
      await repo.save(e);
    }
    return repo;
  }

  Entry entry(String id, String content, String dayKey) => Entry(
        id: id,
        content: content,
        createdAt: DateTime.utc(2026, 10, 28, 8),
        updatedAt: DateTime.utc(2026, 10, 28, 8),
        dayKey: dayKey,
      );

  Future<void> showTimeline(WidgetTester tester, MemoryRepository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePage(
            repository: repo,
            onEdit: (_) {},
            onStart: () {},
            today: today,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AC-01: 有记录 → 卡片显示「连续 N 天」', (tester) async {
    final repo = await seed([
      entry('a', '第一条', '2026-10-30'),
      entry('b', '第二条', '2026-10-29'),
      entry('c', '第三条', '2026-10-28'),
    ]);
    await showTimeline(tester, repo);
    // 昨天 10-30 起连续 3 天，今天未记 → display 3。
    expect(find.text('连续 3 天'), findsOneWidget);
  });

  testWidgets('AC-02: 今天未记 → 提示「今天还没记」并给「写一条」', (tester) async {
    final repo = await seed([entry('a', '昨天记的', '2026-10-30')]);
    await showTimeline(tester, repo);
    expect(find.text('连续 1 天'), findsOneWidget);
    expect(find.text('今天还没记，去写一条'), findsOneWidget);
    expect(find.byKey(const Key('streak-write-today')), findsOneWidget);
  });

  testWidgets('AC-03: 今天已记 → 卡片并入今天，不显示「今天还没记」', (tester) async {
    final repo = await seed([
      entry('a', '今天写的', '2026-10-31'),
      entry('b', '昨天写的', '2026-10-30'),
    ]);
    await showTimeline(tester, repo);
    // current=1（昨天 10-30）+ 今天已记 → display 2。
    expect(find.text('连续 2 天'), findsOneWidget);
    expect(find.textContaining('今天还没记'), findsNothing);
    expect(find.text('今天已记，继续保持'), findsOneWidget);
  });

  testWidgets('AC-04: 无记录 → 卡片显示空状态引导', (tester) async {
    final repo = await seed([]);
    await showTimeline(tester, repo);
    expect(find.text('等待你的第一篇日记'), findsOneWidget);
    expect(find.text('开启你的第一条记录'), findsOneWidget);
    // 时间轴自身的空状态（含「写下第一条」按钮）仍存在。
    expect(find.text('写下第一条'), findsOneWidget);
    expect(find.text('今天还没记'), findsNothing);
  });

  testWidgets('AC-10: 删除一条后，连续天数随之减少', (tester) async {
    final repo = await seed([
      entry('a', '昨天记的', '2026-10-30'),
      entry('b', '前天记的', '2026-10-29'),
      entry('c', '大前天记的', '2026-10-28'),
    ]);
    await showTimeline(tester, repo);
    expect(find.text('连续 3 天'), findsOneWidget);

    // 删除最旧一条（大前天 10-28）：连续段 3→2，不断口。
    await tester.longPress(find.text('大前天记的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-action-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('连续 2 天'), findsOneWidget);
  });

  testWidgets('AC-10: 删除断口处的条目后，连续天数按昨天为界重算', (tester) async {
    // 删除前天（10-29）后，昨天（10-30）与大前天（10-28）之间断开，
    // 昨天为界下只剩昨天这 1 天——验证断口不会让卡片留旧值 3。
    final repo = await seed([
      entry('a', '昨天记的', '2026-10-30'),
      entry('b', '前天记的', '2026-10-29'),
      entry('c', '大前天记的', '2026-10-28'),
    ]);
    await showTimeline(tester, repo);
    expect(find.text('连续 3 天'), findsOneWidget);

    await tester.longPress(find.text('前天记的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-action-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('连续 1 天'), findsOneWidget);
  });
}
