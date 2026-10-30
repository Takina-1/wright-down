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

  testWidgets('编辑已存条目、只改心情不改正文时 mood 仍落库', (tester) async {
    // 暴露 Critical 缺陷：_dirty 只比 content，只改 mood 时 flush 早退，
    // mood 静默不落库（AC-03 失败）。修复后 _dirty 纳入 mood 比较。
    final entry = Entry(
      id: 'existing-1',
      content: '旧正文',
      createdAt: DateTime(2026, 10, 30, 2, 0),
      updatedAt: DateTime(2026, 10, 30, 2, 0),
      dayKey: '2026-10-30',
      mood: 'sad',
    );
    repo.entries[entry.id] = entry;
    await editor.edit(entry);
    // 不改正文，只改心情
    editor.setMood('happy');
    await tester.pump(const Duration(seconds: 2));
    expect(repo.entries[entry.id]!.mood, 'happy');
    // 正文未被改动，仍是原值
    expect(repo.entries[entry.id]!.content, '旧正文');
  });
}
