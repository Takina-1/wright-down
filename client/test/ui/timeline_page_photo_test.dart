import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/timeline_page.dart';

import '../support/memory_repository.dart';

/// 限定在时间轴 ListTile 内按正文查找，避免与随机卡片撞同一文本。
Finder tileText(String text) => find.descendant(
      of: find.byType(ListTile),
      matching: find.text(text),
    );

void main() {
  final created = DateTime.utc(2026, 10, 28, 8);

  Entry entry(String id, String content, {Uint8List? photo}) => Entry(
        id: id,
        content: content,
        createdAt: created,
        updatedAt: created,
        dayKey: '2026-10-28',
        photo: photo,
      );

  Future<MemoryRepository> seed(List<Entry> entries) async {
    final repo = MemoryRepository();
    for (final e in entries) {
      await repo.save(e);
    }
    return repo;
  }

  Future<void> showTimeline(WidgetTester tester, MemoryRepository repo) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePage(
            repository: repo,
            onEdit: (_) {},
            onStart: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AC-04: 带照片条目显示缩略图', (tester) async {
    final photo = Uint8List.fromList([1, 2, 3, 4, 5]);
    final repo = await seed([entry('a', '带照片', photo: photo)]);
    await showTimeline(tester, repo);

    // 缩略图是 Image.memory，限定在 ListTile 作用域内数。
    final images = find.descendant(
      of: find.byType(ListTile),
      matching: find.byType(Image),
    );
    expect(images, findsOneWidget);
  });

  testWidgets('AC-05: 无照片条目不显示缩略图', (tester) async {
    final repo = await seed([entry('a', '无照片')]);
    await showTimeline(tester, repo);

    final images = find.descendant(
      of: find.byType(ListTile),
      matching: find.byType(Image),
    );
    expect(images, findsNothing);
  });

  testWidgets('混合：有照片显示、无照片不显示', (tester) async {
    final repo = await seed([
      entry('a', '带照片', photo: Uint8List.fromList([9, 8, 7])),
      entry('b', '无照片'),
    ]);
    await showTimeline(tester, repo);

    final images = find.descendant(
      of: find.byType(ListTile),
      matching: find.byType(Image),
    );
    expect(images, findsOneWidget);
  });
}
