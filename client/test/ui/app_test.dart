import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/app.dart';

import '../support/memory_repository.dart';

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
}
