import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/trash_page.dart';

import '../support/memory_repository.dart';

void main() {
  late MemoryRepository repository;

  setUp(() async {
    repository = MemoryRepository();
    await repository.save(
      Entry(
        id: 'a',
        content: '写错了',
        createdAt: DateTime.utc(2026, 10, 28, 3),
        updatedAt: DateTime.utc(2026, 10, 28, 3),
        dayKey: '2026-10-28',
      ),
    );
    await repository.softDelete('a');
  });

  testWidgets('回收站列出已删除条目并显示删除时间', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);
    expect(find.text('彻底删除'), findsOneWidget);

    // 删除时间是「年-月-日 时:分」，月、日、时、分都补零到两位。
    final stamp = tester.widget<Text>(
      find.byKey(const Key('trash-deleted-at-a')),
    );
    expect(stamp.data, startsWith('删除于 '));
    expect(
      stamp.data,
      matches(RegExp(r'删除于 \d{4}-\d{2}-\d{2} \d{2}:\d{2}$')),
    );
  });

  testWidgets('恢复后条目离开回收站', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsNothing);
    expect(repository.entries['a']!.deletedAt, isNull);
    expect(find.text('已恢复到回顾'), findsOneWidget);
  });

  testWidgets('彻底删除需要确认，点取消时条目还在', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('彻底删除'));
    await tester.pumpAndSettle();

    // 确认对话框确实弹出来了。
    expect(find.text('彻底删除这条记录？'), findsOneWidget);
    expect(
      find.text('彻底删除后不能再恢复，也无法通过备份找回。'),
      findsOneWidget,
    );

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

    await tester.tap(find.text('彻底删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('彻底删除').last);
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsNothing);
    expect(repository.entries.containsKey('a'), isFalse);
  });

  testWidgets('清空回收站会清掉全部已删除条目', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('清空回收站'));
    await tester.pumpAndSettle();

    expect(find.text('清空回收站？'), findsOneWidget);
    expect(
      find.text('回收站里的所有记录都会被彻底删除，无法恢复。'),
      findsOneWidget,
    );

    await tester.tap(find.text('清空').last);
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsNothing);
    expect(repository.entries.containsKey('a'), isFalse);
    expect(find.text('已清空 1 条'), findsOneWidget);
  });

  testWidgets('清空回收站点取消时什么都不发生', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('清空回收站'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsOneWidget);
    expect(repository.entries.containsKey('a'), isTrue);
  });

  testWidgets('回收站为空时显示空状态', (tester) async {
    final empty = MemoryRepository();
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: empty)));
    await tester.pumpAndSettle();

    expect(find.textContaining('回收站是空的'), findsOneWidget);
    // 空的时候没有「清空回收站」按钮。
    expect(find.text('清空回收站'), findsNothing);
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

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(find.text('恢复失败，请重试'), findsOneWidget);
    expect(find.text('写错了'), findsOneWidget);
    expect(repository.entries['a']!.deletedAt, isNotNull);
  });

  testWidgets('彻底删除失败时给出提示且条目留在回收站', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    repository.failDelete = true;
    await tester.tap(find.text('彻底删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('彻底删除').last);
    await tester.pumpAndSettle();

    expect(find.text('彻底删除失败，请重试'), findsOneWidget);
    expect(find.text('写错了'), findsOneWidget);
    expect(repository.entries.containsKey('a'), isTrue);
  });

  testWidgets('清空失败时给出提示且条目留在回收站', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    repository.failDelete = true;
    await tester.tap(find.text('清空回收站'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空').last);
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
    expect(find.text('恢复'), findsOneWidget);
    expect(find.text('彻底删除'), findsOneWidget);
  });
}
