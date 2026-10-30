import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/timeline_page.dart';

import '../support/memory_repository.dart';

void main() {
  final created = DateTime.utc(2026, 10, 28, 8);

  testWidgets('a short day key does not break the timeline', (tester) async {
    final repo = MemoryRepository();
    // 历史脏数据：早期版本或手工改过的备份可能留下长度不足的 dayKey。
    repo.entries['dirty'] = Entry(
      id: 'dirty',
      content: '一条 dayKey 不合法的旧记录',
      createdAt: created,
      updatedAt: created,
      dayKey: '2026',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePage(repository: repo, onEdit: (_) {}, onStart: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 页面能打开，条目本身仍然读得到。
    expect(tester.takeException(), isNull);
    expect(find.text('一条 dayKey 不合法的旧记录'), findsOneWidget);
    // 月份标题退回用创建时间的本地年月，不抛 RangeError。
    expect(find.textContaining('月'), findsWidgets);
  });

  Future<MemoryRepository> seed() async {
    final repo = MemoryRepository();
    await repo.save(
      Entry(
        id: 'a',
        content: '第一条记录',
        createdAt: created,
        updatedAt: created,
        dayKey: '2026-10-28',
      ),
    );
    return repo;
  }

  Future<void> showTimeline(WidgetTester tester, MemoryRepository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePage(repository: repo, onEdit: (_) {}, onStart: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('长按条目弹出编辑与删除菜单', (tester) async {
    final repo = await seed();
    await showTimeline(tester, repo);

    await tester.longPress(find.text('第一条记录'));
    await tester.pumpAndSettle();

    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('确认删除后条目离开列表并提示可撤销', (tester) async {
    final repo = await seed();
    await showTimeline(tester, repo);

    await tester.longPress(find.text('第一条记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-action-delete')));
    await tester.pumpAndSettle();

    // 确认对话框里有内容摘要
    expect(find.textContaining('第一条记录'), findsWidgets);
    await tester.tap(find.byKey(const Key('timeline-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('第一条记录'), findsNothing);
    expect(find.text('已移到回收站'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    expect(repo.entries['a']!.deletedAt, isNotNull);
  });

  testWidgets('撤销后条目回到列表', (tester) async {
    final repo = await seed();
    await showTimeline(tester, repo);

    await tester.longPress(find.text('第一条记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-action-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-delete-confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(find.text('第一条记录'), findsOneWidget);
    expect(repo.entries['a']!.deletedAt, isNull);
  });

  testWidgets('删除失败时条目仍在并给出失败提示', (tester) async {
    final repo = await seed();
    repo.failDelete = true;
    await showTimeline(tester, repo);

    await tester.longPress(find.text('第一条记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-action-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('第一条记录'), findsOneWidget);
    expect(find.textContaining('删除失败'), findsOneWidget);
  });

  testWidgets('菜单里的编辑会回调 onEdit', (tester) async {
    final repo = await seed();
    Entry? edited;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePage(
            repository: repo,
            onEdit: (entry) => edited = entry,
            onStart: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('第一条记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-action-edit')));
    await tester.pumpAndSettle();

    expect(edited?.id, 'a');
    // 编辑只是回调，不会删除条目。
    expect(find.text('第一条记录'), findsOneWidget);
    expect(repo.entries['a']!.deletedAt, isNull);
  });

  testWidgets('撤销后条目回到原来的排序位置', (tester) async {
    final repo = MemoryRepository();
    await repo.save(
      Entry(
        id: 'old',
        content: '更早的一条',
        createdAt: created.subtract(const Duration(days: 1)),
        updatedAt: created,
        dayKey: '2026-10-27',
      ),
    );
    await repo.save(
      Entry(
        id: 'a',
        content: '第一条记录',
        createdAt: created,
        updatedAt: created,
        dayKey: '2026-10-28',
      ),
    );
    await showTimeline(tester, repo);

    await tester.longPress(find.text('第一条记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-action-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-delete-confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    // 恢复到原位置：仍然排在「更早的一条」前面。
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles.indexOf('第一条记录'), lessThan(titles.indexOf('更早的一条')));
  });
}
