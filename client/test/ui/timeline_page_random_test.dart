import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/timeline_page.dart';

import '../support/memory_repository.dart';

/// 随机一篇卡片的组件测试。
///
/// `randomSeed` 通过 [TimelinePage.randomSeed] 注入固定种子，让首次抽取与
/// 「换一篇」的序列可复现，避免断言随机碰运气。
void main() {
  final created = DateTime.utc(2026, 10, 28, 8);

  Entry entry(
    String id,
    String content, {
    DateTime? deletedAt,
    String dayKey = '2026-10-28',
  }) =>
      Entry(
        id: id,
        content: content,
        createdAt: created,
        updatedAt: created,
        dayKey: dayKey,
        deletedAt: deletedAt,
      );

  /// 随机卡片正文区显示的文本（摘要 + 日期键，用空格拼接）。
  ///
  /// 限定在 `random-card-body` 作用域内取，避免与时间轴上同一正文的
  /// ListTile 撞车（两者都显示同一条 entry.content）。拼接摘要与日期，
  /// 让「换一篇」的断言同时覆盖正文变化与日期变化。
  String randomBodyText(WidgetTester tester) =>
      tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('random-card-body')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .join(' ')
          .trim();

  Future<MemoryRepository> seed(List<Entry> entries) async {
    final repo = MemoryRepository();
    for (final e in entries) {
      await repo.save(e);
    }
    return repo;
  }

  Future<void> showTimeline(WidgetTester tester, MemoryRepository repo, {
    Entry? Function(Entry)? onRandomShow,
    int? randomSeed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePage(
            repository: repo,
            onEdit: (_) {},
            onStart: () {},
            onRandomShow: onRandomShow,
            randomSeed: randomSeed,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AC-01: 有记录 → 卡片显示抽中条目摘要与日期', (tester) async {
    final repo = await seed([
      entry('a', '第一条'),
      entry('b', '第二条'),
      entry('c', '第三条'),
    ]);
    await showTimeline(tester, repo, randomSeed: 1);

    expect(find.text('随便看看'), findsOneWidget);
    // 抽中三条之一，摘要短于 20 字不截断，卡片正文区显示该摘要（含日期键）。
    final body = randomBodyText(tester);
    expect(
      ['第一条 2026-10-28', '第二条 2026-10-28', '第三条 2026-10-28'],
      contains(body),
    );
  });

  testWidgets('AC-02: 点卡片正文 → 回调 onRandomShow 携带抽中条目', (
    tester,
  ) async {
    final repo = await seed([entry('only', '唯一的一条')]);
    Entry? shown;
    await showTimeline(tester, repo, onRandomShow: (e) => shown = e);

    await tester.tap(find.byKey(const Key('random-card-body')));
    await tester.pumpAndSettle();

    expect(shown?.id, 'only');
  });

  testWidgets('AC-03: 点「换一篇」→ 重新抽，摘要变化', (tester) async {
    final repo = await seed([
      entry('a', '第一篇', dayKey: '2026-10-01'),
      entry('b', '第二篇', dayKey: '2026-10-02'),
      entry('c', '第三篇', dayKey: '2026-10-03'),
    ]);
    await showTimeline(tester, repo, randomSeed: 5);

    // 首次抽取的摘要（三篇之一，含各自的日期键）。
    final firstText = randomBodyText(tester);

    await tester.tap(find.byKey(const Key('random-show-another')));
    await tester.pumpAndSettle();

    final secondText = randomBodyText(tester);

    // 种子递增后抽到不同条目：摘要与日期键组合必然变化（三条各配不同日期）。
    expect(firstText, isNot(secondText));
  });

  testWidgets('AC-04: 无记录 → 卡片显示空状态引导', (tester) async {
    final repo = await seed([]);
    await showTimeline(tester, repo);

    expect(find.text('翻开第一页，开始记录'), findsOneWidget);
    // 不显示摘要正文。
    expect(find.byKey(const Key('random-card-body')), findsNothing);
  });

  testWidgets('AC-05: 只有一条 → 抽中它，摘要一致', (tester) async {
    final repo = await seed([entry('only', '唯一记录')]);
    await showTimeline(tester, repo, randomSeed: 0);

    // 限定在卡片正文区，避免与时间轴 ListTile 的同一正文撞车。
    expect(randomBodyText(tester), contains('唯一记录'));
  });

  testWidgets('AC-06: 已删除条目不会被抽中', (tester) async {
    // 一条已删除、一条存活：卡片只能显示存活那条。
    final repo = await seed([
      entry('dead', '已删除的'),
      entry('live', '存活的记录'),
    ]);
    await repo.softDelete('dead');
    await showTimeline(tester, repo, randomSeed: 3);

    expect(randomBodyText(tester), contains('存活的记录'));
    expect(randomBodyText(tester), isNot(contains('已删除的')));
  });

  testWidgets('未提供 onRandomShow 时卡片不响应点击', (tester) async {
    final repo = await seed([entry('only', '唯一的一条')]);
    await showTimeline(tester, repo);

    // onRandomShow 为空时 InkWell.onTap 为 null，点击不抛异常。
    await tester.tap(find.byKey(const Key('random-card-body')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(randomBodyText(tester), contains('唯一的一条'));
  });
}
