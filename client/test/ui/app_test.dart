import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/app.dart';

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
  testWidgets('backgrounding flushes input before the debounce expires', (
    tester,
  ) async {
    final repo = MemoryRepository();
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.enterText(find.byKey(const Key('entry-content')), '后台前保存');
    expect(repo.entries, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(repo.entries.values.single.content, '后台前保存');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('system back after failed save offers to keep editing', (
    tester,
  ) async {
    final repo = MemoryRepository()..failSave = true;
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.enterText(find.byKey(const Key('entry-content')), '退出前保留');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('还有未保存的内容'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('entry-content')), findsOneWidget);
    expect(find.text('退出前保留'), findsOneWidget);
  });

  testWidgets('save failure remains usable on a phone with keyboard visible', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      JournalApp(repository: MemoryRepository()..failSave = true),
    );
    await tester.enterText(find.byKey(const Key('entry-content')), '小屏幕');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('重试保存'), findsOneWidget);
  });

  testWidgets('write, autosave, review and edit the same diary', (
    tester,
  ) async {
    final repo = MemoryRepository();
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('entry-content')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('entry-content')), '今天在公园散步');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('已保存'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    expect(find.text('今天在公园散步'), findsOneWidget);
    await tester.tap(find.text('今天在公园散步'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-content')), '今天在公园看到了猫');
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    expect(find.text('今天在公园看到了猫'), findsOneWidget);
    expect(repo.entries, hasLength(1));
  });

  testWidgets('empty timeline offers a way to start writing', (tester) async {
    await tester.pumpWidget(JournalApp(repository: MemoryRepository()));
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    expect(find.text('还没有记录'), findsOneWidget);
    await tester.tap(find.text('写下第一条'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('entry-content')), findsOneWidget);
  });

  testWidgets('failed save blocks navigation and retry keeps the text', (
    tester,
  ) async {
    final repo = MemoryRepository()..failSave = true;
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.enterText(find.byKey(const Key('entry-content')), '不要丢掉我');
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('entry-content')), findsOneWidget);
    expect(find.text('重试保存'), findsOneWidget);
    expect(repo.entries, isEmpty);
    repo.failSave = false;
    await tester.tap(find.text('重试保存'));
    await tester.pumpAndSettle();
    expect(repo.entries.values.single.content, '不要丢掉我');
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('timeline read failure has a working retry action', (
    tester,
  ) async {
    final repo = MemoryRepository()..failList = true;
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    expect(find.text('读取失败，请重试'), findsOneWidget);
    repo.failList = false;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('还没有记录'), findsOneWidget);
  });

  testWidgets('编辑已有条目时出现删除按钮，新记录时不出现', (tester) async {
    final repo = MemoryRepository();
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.text('删除这条'), findsNothing);
    expect(find.byKey(const Key('composer-delete')), findsNothing);

    // 先写一条并保存，再从回顾页点开它。
    await tester.enterText(find.byKey(const Key('entry-content')), '第一条记录');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一条记录'));
    await tester.pumpAndSettle();

    expect(find.text('删除这条'), findsOneWidget);
    expect(find.byKey(const Key('composer-delete')), findsOneWidget);
  });

  testWidgets('确认删除后编辑器复位并可撤销', (tester) async {
    final repo = MemoryRepository();
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-content')), '第一条记录');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一条记录'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-delete')));
    await tester.pumpAndSettle();
    // 确认框里要有正文摘要和回收站提示。
    expect(find.text('删除这条记录？'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('第一条记录'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('删除后可在回收站找回。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('composer-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('已移到回收站'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    // 编辑器已复位成空白的新记录
    final field = tester.widget<TextField>(
      find.byKey(const Key('entry-content')),
    );
    expect(field.controller!.text, isEmpty);
    expect(repo.entries.values.single.deletedAt, isNotNull);

    // 撤销：条目回到时间轴。
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(repo.entries.values.single.deletedAt, isNull);
  });

  testWidgets('取消删除对话框时条目与编辑器内容都不变', (tester) async {
    final repo = MemoryRepository();
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-content')), '第一条记录');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一条记录'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-delete')));
    await tester.pumpAndSettle();
    expect(find.text('删除这条记录？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('删除这条记录？'), findsNothing);
    expect(repo.entries.values.single.deletedAt, isNull);
    final field = tester.widget<TextField>(
      find.byKey(const Key('entry-content')),
    );
    expect(field.controller!.text, '第一条记录');
    expect(find.text('删除这条'), findsOneWidget);
  });

  testWidgets('删除确认框里的正文摘要截断到二十字', (tester) async {
    final repo = MemoryRepository();
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.pumpAndSettle();
    const long = '这是很长的一段正文内容用来测试截断行为超过二十个字';
    await tester.enterText(find.byKey(const Key('entry-content')), long);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(long));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-delete')));
    await tester.pumpAndSettle();

    final dialogText = tester.widget<Text>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('删除后可在回收站找回。'),
      ),
    );
    expect(dialogText.data, '${long.substring(0, 20)}…\n\n删除后可在回收站找回。');
  });

  testWidgets('删除失败时提示且条目仍在编辑器里', (tester) async {
    final repo = MemoryRepository()..failDelete = true;
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-content')), '第一条记录');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一条记录'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('删除失败'), findsOneWidget);
    expect(find.text('已移到回收站'), findsNothing);
    expect(repo.entries.values.single.deletedAt, isNull);
    final field = tester.widget<TextField>(
      find.byKey(const Key('entry-content')),
    );
    expect(field.controller!.text, '第一条记录');
    // 删除失败不该借用保存错误的界面。
    expect(find.text('重试保存'), findsNothing);
    expect(find.text('保存失败'), findsNothing);
  });

  testWidgets('删除进行中禁用删除与下一条按钮且输入框只读', (tester) async {
    final repo = MemoryRepository();
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-content')), '第一条记录');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一条记录'));
    await tester.pumpAndSettle();

    // 把软删除挂起：删除流程停在半路，界面应进入过渡态。
    final gate = Completer<void>();
    repo.deleteGate = gate;
    await tester.tap(find.byKey(const Key('composer-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-delete-confirm')));
    await tester.pump();

    // 过渡态：两个按钮都禁用，输入框只读。
    expect(
      tester.widget<TextButton>(find.byKey(const Key('composer-delete'))).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '下一条'))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('entry-content'))).readOnly,
      isTrue,
    );

    // 放行删除，条目应被移走。
    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.entries.values.single.deletedAt, isNotNull);
  });

  testWidgets('撤销恢复失败时提示用户到回收站重试', (tester) async {
    final repo = _FailingRestoreRepository();
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-content')), '第一条记录');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一条记录'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('已移到回收站'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    // 恢复失败必须让用户看见，不能只 debugPrint。
    expect(find.text('恢复失败，请到回收站重试'), findsOneWidget);
    // 恢复失败，条目仍在回收站里。
    expect(repo.entries.values.single.deletedAt, isNotNull);
  });

  testWidgets('删除前保存失败时优先提示保存失败原因', (tester) async {
    final repo = MemoryRepository();
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-content')), '第一条记录');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一条记录'));
    await tester.pumpAndSettle();

    // 改了正文又存不下去：删除会先落盘，落盘失败后删除也应被拦下，
    // 提示要指向真正的失败原因——保存失败。
    repo.failSave = true;
    await tester.enterText(find.byKey(const Key('entry-content')), '改过的内容');

    await tester.tap(find.byKey(const Key('composer-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-delete-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('保存失败'),
      ),
      findsOneWidget,
    );
    expect(find.text('已移到回收站'), findsNothing);
    expect(repo.entries.values.single.deletedAt, isNull);
  });
}
