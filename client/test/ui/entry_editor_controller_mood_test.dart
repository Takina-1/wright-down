import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/entry_editor_controller.dart';

import '../support/memory_repository.dart';

void main() {
  late MemoryRepository repo;
  late EntryEditorController editor;
  var seq = 0;
  setUp(() {
    repo = MemoryRepository();
    editor = EntryEditorController(
      repository: repo,
      idGenerator: () => 'entry-${seq++}',
      now: () => DateTime(2026, 10, 30, 2, 0),
    );
  });
  tearDown(() => editor.dispose());

  test('新记录默认 mood 为 null', () {
    expect(editor.mood, isNull);
  });

  testWidgets('setMood 后保存，仓储里的条目带 mood', (tester) async {
    editor.updateContent('今天开心');
    editor.setMood('happy');
    await tester.pump(const Duration(seconds: 2));
    expect(repo.entries.values.single.mood, 'happy');
  });

  testWidgets('clearMood 后保存，仓储里的条目 mood 为 null', (tester) async {
    editor.updateContent('今天开心');
    editor.setMood('happy');
    editor.clearMood();
    await tester.pump(const Duration(seconds: 2));
    expect(repo.entries.values.single.mood, isNull);
  });

  test('edit 载入已有条目时 mood 一并载入', () async {
    final entry = Entry(
      id: 'e', content: '旧',
      createdAt: DateTime(2026, 10, 30, 2, 0),
      updatedAt: DateTime(2026, 10, 30, 2, 0),
      dayKey: '2026-10-30', mood: 'sad',
    );
    await editor.edit(entry);
    expect(editor.mood, 'sad');
  });

  test('newEntry 后 mood 清空', () async {
    editor.updateContent('x');
    editor.setMood('happy');
    await editor.flush();
    await editor.newEntry();
    expect(editor.mood, isNull);
  });
}
