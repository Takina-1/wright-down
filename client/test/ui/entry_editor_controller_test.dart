import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/entry_editor_controller.dart';

import '../support/memory_repository.dart';

void main() {
  late MemoryRepository repo;
  late EntryEditorController editor;
  var sequence = 0;
  setUp(() {
    repo = MemoryRepository();
    editor = EntryEditorController(
      repository: repo,
      idGenerator: () => 'entry-${sequence++}',
      now: () => DateTime(2026, 10, 28, 18),
    );
  });
  tearDown(() => editor.dispose());

  testWidgets('autosave waits one second since the last input', (tester) async {
    editor.updateContent('first');
    await tester.pump(const Duration(milliseconds: 800));
    expect(repo.saves, 0);
    editor.updateContent('latest');
    await tester.pump(const Duration(milliseconds: 999));
    expect(repo.saves, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(repo.entries.values.single.content, 'latest');
    expect(editor.status, SaveStatus.saved);
  });

  testWidgets('whitespace creates no record', (tester) async {
    editor.updateContent(' \n ');
    await tester.pump(const Duration(seconds: 2));
    expect(repo.saves, 0);
    expect(await editor.newEntry(), isTrue);
    expect(editor.content, isEmpty);
  });

  testWidgets('failed save keeps text and blocks next entry until retry', (
    tester,
  ) async {
    repo.failSave = true;
    editor.updateContent('must survive');
    expect(await editor.newEntry(), isFalse);
    expect(editor.content, 'must survive');
    expect(editor.status, SaveStatus.error);
    expect(editor.error, isNotNull);
    repo.failSave = false;
    expect(await editor.flush(), isTrue);
    expect(repo.entries.values.single.content, 'must survive');
    expect(editor.status, SaveStatus.saved);
    expect(await editor.newEntry(), isTrue);
    expect(editor.content, isEmpty);
  });

  testWidgets(
    'slow save cannot mark newer input saved or create duplicate rows',
    (tester) async {
      repo.gate = Completer<void>();
      editor.updateContent('old');
      final saving = editor.flush();
      await tester.pump();
      editor.updateContent('new');
      expect(editor.hasPendingChanges, isTrue);
      expect(editor.status, isNot(SaveStatus.saved));
      repo.gate!.complete();
      expect(await saving, isTrue);
      expect(repo.entries, hasLength(1));
      expect(repo.entries.values.single.content, 'new');
      expect(editor.hasPendingChanges, isFalse);
    },
  );

  testWidgets('editing preserves id and creation time', (tester) async {
    final original = Entry(
      id: 'existing',
      content: 'before',
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
      dayKey: '2025-01-01',
    );
    repo.entries[original.id] = original;
    expect(await editor.edit(original), isTrue);
    editor.updateContent('after');
    expect(await editor.flush(), isTrue);
    expect(repo.entries, hasLength(1));
    expect(repo.entries['existing']!.createdAt, original.createdAt);
    expect(repo.entries['existing']!.dayKey, original.dayKey);
    expect(repo.entries['existing']!.content, 'after');
  });

  testWidgets('clearing existing text does not silently erase a saved record', (
    tester,
  ) async {
    editor.updateContent('keep');
    await editor.flush();
    editor.updateContent('  ');
    expect(await editor.flush(), isFalse);
    expect(editor.status, SaveStatus.error);
    expect(repo.entries.values.single.content, 'keep');
    expect(editor.hasPendingChanges, isTrue);
  });
}
