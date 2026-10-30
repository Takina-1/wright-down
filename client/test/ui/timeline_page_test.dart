import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/timeline_page.dart';

import '../support/memory_repository.dart';

/// 恢复必定失败的仓储，用来验证「撤销失败必须给用户提示」。
///
/// 只覆盖 [MemoryRepository.restore]，其余行为与生产仓储一致。
class _FailingRestoreRepository extends MemoryRepository {
  @override
  Future<void> restore(String id) async {
    throw StateError('simulated restore failure');
  }
}

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

  /// 时间轴上按显示顺序排列的条目正文。
  ///
  /// 限定在 [ListView] 内部，避免命中底部弹窗、对话框里的其它 [ListTile]。
  List<String> timelineTitles(WidgetTester tester) => tester
      .widgetList<ListTile>(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(ListTile),
        ),
      )
      .map((tile) => (tile.title as Text).data!)
      .toList();

  /// 长按条目 → 底部菜单点删除 → 确认对话框点确认。
  Future<void> deleteEntry(WidgetTester tester, String title) async {
    await tester.longPress(find.text(title));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-action-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-delete-confirm')));
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

    // 确认对话框里有内容摘要。限定在对话框作用域里，否则列表里那条
    // 也会被命中，断言失去鉴别力。
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('第一条记录'),
      ),
      findsOneWidget,
    );
    // 对话框要说明删除后还能在回收站找回。
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('删除后可在回收站找回。'),
      ),
      findsOneWidget,
    );

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

    await deleteEntry(tester, '第一条记录');

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(find.text('第一条记录'), findsOneWidget);
    expect(repo.entries['a']!.deletedAt, isNull);
  });

  testWidgets('删除失败时条目仍在并给出失败提示', (tester) async {
    final repo = await seed();
    repo.failDelete = true;
    await showTimeline(tester, repo);

    await deleteEntry(tester, '第一条记录');

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

  testWidgets('在确认对话框点取消不会删除条目', (tester) async {
    final repo = await seed();
    await showTimeline(tester, repo);

    await tester.longPress(find.text('第一条记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-action-delete')));
    await tester.pumpAndSettle();

    // 点「取消」而不是「删除」。
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('取消'),
      ),
    );
    await tester.pumpAndSettle();

    // 条目还在列表里，仓库里也没有打上删除标记。
    expect(find.text('第一条记录'), findsOneWidget);
    expect(repo.entries['a']!.deletedAt, isNull);
    // 取消不弹「已移到回收站」的提示。
    expect(find.text('已移到回收站'), findsNothing);
    expect(find.text('撤销'), findsNothing);
  });

  testWidgets('撤销后条目回到原来的排序位置', (tester) async {
    final repo = MemoryRepository();
    // 三条记录，创建时间依次递减：第三条最新、第二条居中、第一条最旧。
    // 时间轴按「创建时间倒序」显示，列表顺序应是 [第三条, 第二条, 第一条]。
    await repo.save(
      Entry(
        id: 'c',
        content: '第三条记录',
        createdAt: created,
        updatedAt: created,
        dayKey: '2026-10-28',
      ),
    );
    await repo.save(
      Entry(
        id: 'b',
        content: '第二条记录',
        createdAt: created.subtract(const Duration(hours: 1)),
        updatedAt: created,
        dayKey: '2026-10-28',
      ),
    );
    await repo.save(
      Entry(
        id: 'a',
        content: '第一条记录',
        createdAt: created.subtract(const Duration(hours: 2)),
        updatedAt: created,
        dayKey: '2026-10-27',
      ),
    );
    await showTimeline(tester, repo);
    expect(timelineTitles(tester), ['第三条记录', '第二条记录', '第一条记录']);

    // 删掉中间那条。
    await deleteEntry(tester, '第二条记录');
    expect(timelineTitles(tester), ['第三条记录', '第一条记录']);

    // 撤销后必须回到原来的位置。用完整顺序断言，不用两两 indexOf 比较：
    // 「永远插到最前」和「插到正确位置」在 indexOf 比较下同样成立，
    // 只有完整顺序才能区分。
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(timelineTitles(tester), ['第三条记录', '第二条记录', '第一条记录']);
    expect(repo.entries['b']!.deletedAt, isNull);
  });

  testWidgets('删除已加载的最旧条目后继续加载不会重复也不会跳过', (
    tester,
  ) async {
    // 视口放大到能一次放下 60 条，方便断言完整列表。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 20000);
    addTearDown(tester.view.reset);

    final repo = MemoryRepository();
    // 60 条记录：创建时间严格递减，ID 也严格递减（与「同刻按 ID 倒序」
    // 的排序口径一致），所以列表顺序完全确定：
    // [条目60, 条目59, ..., 条目01]，条目60 最新。
    for (var i = 0; i < 60; i++) {
      final n = 60 - i;
      await repo.save(
        Entry(
          id: 'e$n',
          content: '条目${n.toString().padLeft(2, '0')}',
          createdAt: created.subtract(Duration(minutes: i)),
          updatedAt: created,
          dayKey: '2026-10-28',
        ),
      );
    }
    await showTimeline(tester, repo);

    // 第一页只加载 30 条。
    expect(timelineTitles(tester).length, 30);
    expect(timelineTitles(tester).first, '条目60');
    expect(timelineTitles(tester).last, '条目31');

    // 删掉已加载列表里最旧的那条（第 30 条，条目31）。
    await deleteEntry(tester, '条目31');
    expect(timelineTitles(tester).length, 29);
    expect(timelineTitles(tester).last, '条目32');

    // 继续加载。删除后列表游标退到次旧的一条（条目32），
    // 「多出来的那一段」只包含已删除的条目31，而仓储的 list() 只返回
    // 未删除的条目，所以既不会重复也不会跳过。
    for (var i = 0; i < 3 && find.text('查看更多').evaluate().isNotEmpty; i++) {
      await tester.tap(find.text('查看更多'));
      await tester.pumpAndSettle();
    }

    final titles = timelineTitles(tester);
    // 没有重复条目。
    expect(titles.toSet().length, titles.length);
    // 被删掉的那条不在列表里。
    expect(titles, isNot(contains('条目31')));
    // 第 30 条之后到第 60 条的条目都还在，没有被永久跳过。
    for (var n = 1; n <= 30; n++) {
      expect(titles, contains('条目${n.toString().padLeft(2, '0')}'));
    }
    // 完整顺序：60 条原始条目减去被删的 1 条 = 59 条，且顺序正确。
    expect(titles.length, 59);
    expect(titles.first, '条目60');
    expect(titles[28], '条目32');
    expect(titles[29], '条目30');
    expect(titles.last, '条目01');
  });

  testWidgets('删除确认框里的正文摘要截断到二十字', (tester) async {
    final repo = MemoryRepository();
    const long = '这是很长的一段正文内容用来测试截断行为超过二十个字';
    await repo.save(
      Entry(
        id: 'long',
        content: long,
        createdAt: created,
        updatedAt: created,
        dayKey: '2026-10-28',
      ),
    );
    await showTimeline(tester, repo);

    await tester.longPress(find.text(long));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-action-delete')));
    await tester.pumpAndSettle();

    // 确认框里显示的是前 20 字加省略号，不是完整正文。
    final dialogText = tester.widget<Text>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('删除后可在回收站找回。'),
      ),
    );
    expect(dialogText.data, '${long.substring(0, 20)}…\n\n删除后可在回收站找回。');
  });

  testWidgets('撤销失败时提示用户到回收站重试', (tester) async {
    final repo = _FailingRestoreRepository();
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

    await deleteEntry(tester, '第一条记录');

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    // 恢复失败必须让用户看见，不能只 debugPrint。
    expect(find.text('恢复失败，请到回收站重试'), findsOneWidget);
    // 恢复失败时条目不放回列表。
    expect(find.text('第一条记录'), findsNothing);
  });

  testWidgets('页面已卸载时撤销仍能恢复数据库里的条目', (tester) async {
    final repo = await seed();

    // 回顾页挂在可切换的容器里：切走后 TimelinePage 的 State 被卸载，
    // 但 SnackBar 挂在 app 级的 ScaffoldMessenger 上，仍然活着。
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, shown, _) => Column(
              children: [
                Expanded(
                  child: shown
                      ? TimelinePage(
                          repository: repo,
                          onEdit: (_) {},
                          onStart: () {},
                        )
                      : const Text('已离开回顾页'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await deleteEntry(tester, '第一条记录');
    expect(repo.entries['a']!.deletedAt, isNotNull);

    // 切走页面，TimelinePage 的 State 被卸载。
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.text('第一条记录'), findsNothing);

    // SnackBar 还在，撤销依然可用，而且不能碰到已卸载的 State。
    expect(find.text('撤销'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 数据库里恢复了。界面不刷新（页面已卸载），刷新交给用户重新进入。
    expect(repo.entries['a']!.deletedAt, isNull);
  });

  testWidgets('页面已卸载且恢复失败时不崩溃', (tester) async {
    final repo = _FailingRestoreRepository();
    await repo.save(
      Entry(
        id: 'a',
        content: '第一条记录',
        createdAt: created,
        updatedAt: created,
        dayKey: '2026-10-28',
      ),
    );

    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, shown, _) => Column(
              children: [
                Expanded(
                  child: shown
                      ? TimelinePage(
                          repository: repo,
                          onEdit: (_) {},
                          onStart: () {},
                        )
                      : const Text('已离开回顾页'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await deleteEntry(tester, '第一条记录');

    visible.value = false;
    await tester.pumpAndSettle();

    // 恢复失败时不能去碰已卸载 State 的 context（会抛 FlutterError）。
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.entries['a']!.deletedAt, isNotNull);
  });
}
