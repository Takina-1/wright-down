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

  test('新记录不可删除', () async {
    final controller = EntryEditorController(
      repository: repo,
      idGenerator: () => 'new-1',
      now: () => DateTime.utc(2026, 10, 28),
    );
    addTearDown(controller.dispose);
    controller.updateContent('还没保存的内容');
    expect(controller.canDelete, isFalse);
    expect(controller.currentEntryId, isNull);
  });

  test('编辑已有条目时可以删除，删除后编辑器复位', () async {
    final controller = EntryEditorController(
      repository: repo,
      idGenerator: () => 'unused',
      now: () => DateTime.utc(2026, 10, 28),
    );
    addTearDown(controller.dispose);
    final entry = Entry(
      id: 'saved-1',
      content: '写错了',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
      dayKey: '2026-10-28',
    );
    repo.entries[entry.id] = entry;
    await controller.edit(entry);
    expect(controller.canDelete, isTrue);
    expect(controller.currentEntryId, 'saved-1');

    expect(await controller.deleteCurrent(), isTrue);

    expect(controller.canDelete, isFalse);
    expect(controller.currentEntryId, isNull);
    expect(controller.content, isEmpty);
    expect(controller.status, SaveStatus.empty);
    expect(repo.entries['saved-1']!.deletedAt, isNotNull);
  });

  test('删除失败时保留内容并给出错误', () async {
    final controller = EntryEditorController(
      repository: repo,
      idGenerator: () => 'unused',
      now: () => DateTime.utc(2026, 10, 28),
    );
    addTearDown(controller.dispose);
    final entry = Entry(
      id: 'saved-1',
      content: '写错了',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
      dayKey: '2026-10-28',
    );
    repo.entries[entry.id] = entry;
    await controller.edit(entry);
    repo.failDelete = true;

    expect(await controller.deleteCurrent(), isFalse);
    expect(controller.content, '写错了');
    // 删除错误单独走 deleteError：不占用保存的状态与错误字段，
    // 否则界面会同时显示「保存失败」和「重试保存」。
    expect(controller.deleteError, '删除失败，这条记录仍在。');
    expect(controller.error, isNull);
    expect(controller.status, isNot(SaveStatus.error));
    expect(repo.entries['saved-1']!.deletedAt, isNull);
  });

  test('正文被清空后仍能删除', () async {
    final controller = EntryEditorController(
      repository: repo,
      idGenerator: () => 'unused',
      now: () => DateTime.utc(2026, 10, 28),
    );
    addTearDown(controller.dispose);
    final entry = Entry(
      id: 'saved-1',
      content: '原内容',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
      dayKey: '2026-10-28',
    );
    repo.entries[entry.id] = entry;
    await controller.edit(entry);

    // 清空正文：这是「保存」规则会拒绝的场景，但删除必须放行。
    controller.updateContent('');
    expect(controller.status, SaveStatus.editing);

    expect(await controller.deleteCurrent(), isTrue);

    expect(controller.content, isEmpty);
    expect(controller.canDelete, isFalse);
    expect(repo.entries['saved-1']!.deletedAt, isNotNull);
    // 正文为空时跳过落盘，库里留的还是删除前的内容。
    expect(repo.entries['saved-1']!.content, '原内容');
  });

  test('删除前先落盘未保存的修改', () async {
    final controller = EntryEditorController(
      repository: repo,
      idGenerator: () => 'unused',
      now: () => DateTime.utc(2026, 10, 28),
    );
    addTearDown(controller.dispose);
    final entry = Entry(
      id: 'saved-1',
      content: '旧内容',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
      dayKey: '2026-10-28',
    );
    repo.entries[entry.id] = entry;
    await controller.edit(entry);
    controller.updateContent('最新内容');

    expect(await controller.deleteCurrent(), isTrue);

    expect(repo.entries['saved-1']!.content, '最新内容');
    expect(repo.entries['saved-1']!.deletedAt, isNotNull);
  });

  testWidgets('删除会等在飞行的保存落地，迟到的保存不会冲掉复位', (
    tester,
  ) async {
    final controller = EntryEditorController(
      repository: repo,
      idGenerator: () => 'unused',
      now: () => DateTime.utc(2026, 10, 28),
    );
    addTearDown(controller.dispose);
    final entry = Entry(
      id: 'saved-1',
      content: '原内容',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
      dayKey: '2026-10-28',
    );
    repo.entries[entry.id] = entry;
    await controller.edit(entry);

    // 一次保存正在飞行，同时用户把正文清空了。
    repo.gate = Completer<void>();
    controller.updateContent('最新内容');
    final saving = controller.flush();
    controller.updateContent('');

    final deleting = controller.deleteCurrent();
    // 让删除先跑起来（修复后它会挂在等在飞行的保存上），再放行保存。
    await tester.pump(const Duration(milliseconds: 20));
    repo.gate!.complete();

    expect(await deleting, isTrue);
    await saving;

    // 迟到的保存没有把控制器改回「正文不能为空，原记录仍保留」的错误态。
    expect(controller.content, isEmpty);
    expect(controller.status, isNot(SaveStatus.error));
    expect(controller.error, isNull);
    expect(controller.deleteError, isNull);
    expect(controller.hasPendingChanges, isFalse);
    expect(repo.entries['saved-1']!.deletedAt, isNotNull);
  });

  testWidgets('删除失败的文案不会被防抖定时器覆盖', (tester) async {
    final controller = EntryEditorController(
      repository: repo,
      idGenerator: () => 'unused',
      now: () => DateTime.utc(2026, 10, 28),
    );
    addTearDown(controller.dispose);
    final entry = Entry(
      id: 'saved-1',
      content: '原内容',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
      dayKey: '2026-10-28',
    );
    repo.entries[entry.id] = entry;
    await controller.edit(entry);

    // 清空正文：1 秒防抖定时器还活着，稍后会自己触发一次 flush()。
    controller.updateContent('');
    repo.failDelete = true;

    expect(await controller.deleteCurrent(), isFalse);
    expect(controller.deleteError, '删除失败，这条记录仍在。');
    expect(controller.error, isNull);
    expect(controller.status, isNot(SaveStatus.error));

    // 等过 1 秒：定时器若还活着，flush() 会把「正文不能为空，原记录仍保留。」
    // 写进保存的错误字段，把删除失败的提示冲掉。
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(controller.deleteError, '删除失败，这条记录仍在。');
    expect(controller.error, isNull);
    expect(controller.status, isNot(SaveStatus.error));
    expect(repo.entries['saved-1']!.deletedAt, isNull);
  });

  test('存储错误时中止删除，记录仍在', () async {
    final controller = EntryEditorController(
      repository: repo,
      idGenerator: () => 'unused',
      now: () => DateTime.utc(2026, 10, 28),
    );
    addTearDown(controller.dispose);
    final entry = Entry(
      id: 'saved-1',
      content: '旧内容',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
      dayKey: '2026-10-28',
    );
    repo.entries[entry.id] = entry;
    await controller.edit(entry);
    repo.failSave = true;
    controller.updateContent('新内容');

    // 落盘失败必须中止删除，否则会把没存住的新内容一起删掉。
    expect(await controller.deleteCurrent(), isFalse);
    expect(repo.entries['saved-1']!.deletedAt, isNull);
    expect(repo.entries['saved-1']!.content, '旧内容');
  });

  test('保存失败的新记录不可删除', () async {
    final controller = EntryEditorController(
      repository: repo,
      idGenerator: () => 'entry-1',
      now: () => DateTime.utc(2026, 10, 28),
    );
    addTearDown(controller.dispose);
    repo.failSave = true;
    controller.updateContent('还没落库的内容');

    expect(await controller.flush(), isFalse);
    // 保存失败后 _id 已经被分配，但从未落库：不能当成可删除的条目。
    expect(controller.canDelete, isFalse);
    expect(controller.currentEntryId, isNull);
  });

  test('删除后再新建的记录重新计算日期，不继承被删条目', () async {
    final controller = EntryEditorController(
      repository: repo,
      idGenerator: () => 'new-after-delete',
      now: () => DateTime(2026, 11, 5, 9),
    );
    addTearDown(controller.dispose);
    final entry = Entry(
      id: 'saved-1',
      content: '原内容',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
      dayKey: '2026-10-28',
    );
    repo.entries[entry.id] = entry;
    await controller.edit(entry);

    expect(await controller.deleteCurrent(), isTrue);
    expect(controller.status, SaveStatus.empty);

    controller.updateContent('新的记录');
    expect(await controller.flush(), isTrue);

    final created = repo.entries['new-after-delete']!;
    expect(created.dayKey, '2026-11-05');
    expect(created.createdAt, DateTime(2026, 11, 5, 9));
  });
}
