import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/ui/home_page.dart';

import '../support/memory_repository.dart';

Future<void> _pumpHome(WidgetTester tester, MemoryRepository repo) async {
  await tester.pumpWidget(
    MaterialApp(home: HomePage(repository: repo)),
  );
  await tester.pumpAndSettle();
}

/// 输入正文并等防抖保存落库。
Future<void> _saveContent(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('entry-content')), text);
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('AC-01: 添加标签后保存，条目带标签', (tester) async {
    final repo = MemoryRepository();
    await _pumpHome(tester, repo);
    await _saveContent(tester, '今天去旅行了');

    await tester.enterText(find.byKey(const Key('tag-input')), '旅行');
    await tester.tap(find.byKey(const Key('tag-add')));
    await tester.pumpAndSettle();
    // 等待防抖保存。
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('旅行'), findsWidgets);
    expect(repo.entries.values.single.tags, ['旅行']);
  });

  testWidgets('AC-01: 回车也能添加标签', (tester) async {
    final repo = MemoryRepository();
    await _pumpHome(tester, repo);
    await _saveContent(tester, '一本书');

    await tester.enterText(find.byKey(const Key('tag-input')), '读书');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    expect(repo.entries.values.single.tags, ['读书']);
  });

  testWidgets('AC-02: 移除标签后保存，条目标签更新', (tester) async {
    final repo = MemoryRepository();
    await _pumpHome(tester, repo);
    await _saveContent(tester, '旅行记录');

    // 先加两个标签。
    await tester.enterText(find.byKey(const Key('tag-input')), '旅行');
    await tester.tap(find.byKey(const Key('tag-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tag-input')), '拍照');
    await tester.tap(find.byKey(const Key('tag-add')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(repo.entries.values.single.tags, ['旅行', '拍照']);

    // 移除「拍照」。
    await tester.tap(find.byKey(const Key('tag-chip-拍照')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('tag-chip-拍照')), findsNothing);
    expect(repo.entries.values.single.tags, ['旅行']);
  });

  testWidgets('AC-06: 重复标签自动去重', (tester) async {
    final repo = MemoryRepository();
    await _pumpHome(tester, repo);
    await _saveContent(tester, '记录');

    await tester.enterText(find.byKey(const Key('tag-input')), '旅行');
    await tester.tap(find.byKey(const Key('tag-add')));
    await tester.pumpAndSettle();
    // 再加一次重复的。
    await tester.enterText(find.byKey(const Key('tag-input')), '旅行');
    await tester.tap(find.byKey(const Key('tag-add')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    expect(repo.entries.values.single.tags, ['旅行']);
  });

  testWidgets('AC-06: 空标签输入忽略', (tester) async {
    final repo = MemoryRepository();
    await _pumpHome(tester, repo);
    await _saveContent(tester, '记录');

    await tester.enterText(find.byKey(const Key('tag-input')), '   ');
    await tester.tap(find.byKey(const Key('tag-add')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    expect(repo.entries.values.single.tags, isEmpty);
  });
}
