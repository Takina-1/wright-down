import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/trash_page.dart';

import '../support/memory_repository.dart';

/// 固定时钟：软删除把墙钟时间转成 UTC 存，界面取出时再转回本地时间，
/// 往返后墙钟不变，因此断言与运行机器的时区无关。
DateTime _fixedNow() => DateTime(2026, 10, 28, 3, 5);

/// 构造一条已删除的条目。
Entry _deletedEntry(String id) => Entry(
  id: id,
  content: '写错了',
  createdAt: DateTime.utc(2026, 10, 28, 3),
  updatedAt: DateTime.utc(2026, 10, 28, 3),
  dayKey: '2026-10-28',
);

/// 回收站里出现了一条没有删除时间的条目（正常流程不会发生，
/// 但界面必须给出占位文案，而不是渲染出悬空的「删除于 」）。
class _MissingDeletedAtRepository extends MemoryRepository {
  _MissingDeletedAtRepository() : super(now: _fixedNow);

  @override
  Future<List<Entry>> listDeleted({int limit = 30}) async => [
    Entry(
      id: 'x',
      content: '没有删除时间',
      createdAt: DateTime.utc(2026, 10, 28, 3),
      updatedAt: DateTime.utc(2026, 10, 28, 3),
      dayKey: '2026-10-28',
    ),
  ];
}

/// 记录页面请求的 limit，用来验证回收站只取了一页（30 条）。
class _RecordingRepository extends MemoryRepository {
  _RecordingRepository() : super(now: _fixedNow);

  /// 页面最近一次调用 [listDeleted] 时传的 limit。
  int? lastLimit;

  @override
  Future<List<Entry>> listDeleted({int limit = 30}) async {
    lastLimit = limit;
    return super.listDeleted(limit: limit);
  }
}

void main() {
  late MemoryRepository repository;

  setUp(() async {
    repository = MemoryRepository(now: _fixedNow);
    await repository.save(_deletedEntry('a'));
    await repository.softDelete('a');
  });

  testWidgets('回收站列出已删除条目并显示删除时间', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsOneWidget);
    expect(find.byKey(const Key('trash-restore-a')), findsOneWidget);
    expect(find.byKey(const Key('trash-purge-a')), findsOneWidget);

    // 删除时间是「年-月-日 时:分」，月、日、时、分都补零到两位；
    // 断言精确值而不只是格式：取值必须来自 deletedAt，而不是 createdAt。
    final stamp = tester.widget<Text>(
      find.byKey(const Key('trash-deleted-at-a')),
    );
    expect(stamp.data, '删除于 2026-10-28 03:05');
  });

  testWidgets('恢复后条目离开回收站', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trash-restore-a')));
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsNothing);
    expect(repository.entries['a']!.deletedAt, isNull);
    expect(find.text('已恢复到回顾'), findsOneWidget);
  });

  testWidgets('彻底删除需要确认，点取消时条目还在', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trash-purge-a')));
    await tester.pumpAndSettle();

    // 确认对话框确实弹出来了。
    expect(find.text('彻底删除这条记录？'), findsOneWidget);
    expect(
      find.text('彻底删除后不能再恢复，也无法通过备份找回。'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('trash-purge-confirm')), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 取消了就不能删。
    expect(find.text('写错了'), findsOneWidget);
    expect(repository.entries.containsKey('a'), isTrue);
    expect(repository.entries['a']!.deletedAt, isNotNull);
  });

  testWidgets('彻底删除需要确认，确认后条目消失', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trash-purge-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trash-purge-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsNothing);
    expect(repository.entries.containsKey('a'), isFalse);
  });

  testWidgets('清空回收站会清掉全部已删除条目', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trash-purge-all')));
    await tester.pumpAndSettle();

    expect(find.text('清空回收站？'), findsOneWidget);
    expect(
      find.text('回收站里的所有记录都会被彻底删除，无法恢复。'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('trash-purge-all-confirm')), findsOneWidget);

    await tester.tap(find.byKey(const Key('trash-purge-all-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsNothing);
    expect(repository.entries.containsKey('a'), isFalse);
    expect(find.text('已清空 1 条'), findsOneWidget);
  });

  testWidgets('清空回收站点取消时什么都不发生', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trash-purge-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsOneWidget);
    expect(repository.entries.containsKey('a'), isTrue);
  });

  testWidgets('回收站为空时显示空状态', (tester) async {
    final empty = MemoryRepository(now: _fixedNow);
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: empty)));
    await tester.pumpAndSettle();

    expect(find.textContaining('回收站是空的'), findsOneWidget);
    // 空的时候没有「清空回收站」按钮。
    expect(find.byKey(const Key('trash-purge-all')), findsNothing);
  });

  testWidgets('读取失败时给出重试入口', (tester) async {
    repository.failListDeleted = true;
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    expect(find.text('读取失败，请重试'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);

    // 修好后重新加载就能看到内容。
    repository.failListDeleted = false;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsOneWidget);
  });

  testWidgets('恢复失败时给出提示且条目留在回收站', (tester) async {
    repository.failRestore = true;
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trash-restore-a')));
    await tester.pumpAndSettle();

    expect(find.text('恢复失败，请重试'), findsOneWidget);
    expect(find.text('写错了'), findsOneWidget);
    expect(repository.entries['a']!.deletedAt, isNotNull);
  });

  testWidgets('彻底删除失败时给出提示且条目留在回收站', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    repository.failDelete = true;
    await tester.tap(find.byKey(const Key('trash-purge-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trash-purge-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('彻底删除失败，请重试'), findsOneWidget);
    expect(find.text('写错了'), findsOneWidget);
    expect(repository.entries.containsKey('a'), isTrue);
  });

  testWidgets('清空失败时给出提示且条目留在回收站', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    repository.failDelete = true;
    await tester.tap(find.byKey(const Key('trash-purge-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trash-purge-all-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('清空失败，请重试'), findsOneWidget);
    expect(find.text('写错了'), findsOneWidget);
    expect(repository.entries.containsKey('a'), isTrue);
  });

  testWidgets('窄屏下两个操作按钮都不会被裁掉', (tester) async {
    // 320x640 是常见的小屏尺寸。按钮放在 subtitle 里而不是 trailing，
    // 这样两枚文字按钮不会被 trailing 的宽度限制挤掉。
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // findsOneWidget 只证明 widget 在树里，不证明它没被裁掉，
    // 所以这里直接量按钮在屏幕上的位置：必须完整落在 320 宽的视口内。
    final restore = tester.getRect(find.byKey(const Key('trash-restore-a')));
    final purge = tester.getRect(find.byKey(const Key('trash-purge-a')));
    for (final rect in [restore, purge]) {
      expect(rect.left, greaterThanOrEqualTo(0), reason: '按钮左侧被裁掉');
      expect(rect.right, lessThanOrEqualTo(320), reason: '按钮右侧被裁掉');
    }

    // 光看横向还不够：按钮回到 ListTile.trailing 时它们仍在屏幕内，
    // 但正文会被 trailing 挤成一条窄柱。所以再断言按钮独占一行——
    // 按钮的上沿必须在删除时间这一行的下沿之后，正文宽度也不会被压窄。
    final deletedAt = tester.getRect(
      find.byKey(const Key('trash-deleted-at-a')),
    );
    expect(restore.top, greaterThanOrEqualTo(deletedAt.bottom));
    expect(purge.top, greaterThanOrEqualTo(deletedAt.bottom));

    final content = tester.getRect(find.text('写错了'));
    expect(content.width, greaterThan(200), reason: '正文被按钮挤窄了');
  });

  testWidgets('超过一页时提示只显示最近 30 条', (tester) async {
    final many = _RecordingRepository();
    for (var i = 0; i < 35; i++) {
      await many.save(_deletedEntry('e$i'));
      await many.softDelete('e$i');
    }

    // 库里确实有 35 条已删除条目，界面只取一页 30 条。
    expect((await many.listDeleted(limit: 100)).length, 35);

    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: many)));
    await tester.pumpAndSettle();

    expect(many.lastLimit, 30, reason: '页面应当只取一页');

    // 提示在列表最底部，30 条卡片要滚到底才看得见。
    await tester.scrollUntilVisible(
      find.text('仅显示最近 30 条，更早的记录不会出现在这里。'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('仅显示最近 30 条，更早的记录不会出现在这里。'),
      findsOneWidget,
    );
  });

  testWidgets('不超过一页时不显示超出提示', (tester) async {
    final few = MemoryRepository(now: _fixedNow);
    for (var i = 0; i < 29; i++) {
      await few.save(_deletedEntry('e$i'));
      await few.softDelete('e$i');
    }

    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: few)));
    await tester.pumpAndSettle();

    expect(
      find.text('仅显示最近 30 条，更早的记录不会出现在这里。'),
      findsNothing,
    );
  });

  testWidgets('缺少删除时间时显示占位文案而不是悬空的「删除于 」', (
    tester,
  ) async {
    final missing = _MissingDeletedAtRepository();
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: missing)));
    await tester.pumpAndSettle();

    final stamp = tester.widget<Text>(
      find.byKey(const Key('trash-deleted-at-x')),
    );
    expect(stamp.data, '删除于 未知时间');
    // 不是悬空的「删除于 」加一个尾随空格。
    expect(stamp.data, isNot('删除于 '));
  });
}
