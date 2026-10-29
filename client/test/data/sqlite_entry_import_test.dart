import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late SqliteEntryRepository repo;
  final time = DateTime.utc(2026, 10, 28, 8);

  Entry entry(
    String id,
    String content, {
    DateTime? createdAt,
    DateTime? updatedAt,
    String dayKey = '2026-10-28',
  }) => Entry(
    id: id,
    content: content,
    createdAt: createdAt ?? time,
    updatedAt: updatedAt ?? time,
    dayKey: dayKey,
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('local_diary_import_');
    repo = SqliteEntryRepository(
      factory: databaseFactoryFfi,
      path: '${temp.path}/journal.db',
    );
  });
  tearDown(() async {
    await repo.close();
    await temp.delete(recursive: true);
  });

  test('exportAll returns every entry, not only the first page', () async {
    for (var i = 0; i < 40; i++) {
      await repo.save(entry('id-${i.toString().padLeft(2, '0')}', '第 $i 条'));
    }
    final exported = await repo.exportAll();
    expect(exported, hasLength(40));
    expect(exported.first.id, 'id-39');
    expect(exported.last.id, 'id-00');
  });

  test('a new id from a backup is inserted', () async {
    final summary = await repo.importAll([entry('a', '来自备份')]);
    expect(summary.inserted, 1);
    expect(summary.updated, 0);
    expect(summary.skipped, 0);
    expect((await repo.list()).single.content, '来自备份');
  });

  test(
    'a newer backup entry updates content but keeps creation time',
    () async {
      await repo.save(entry('a', '本机内容', createdAt: time));
      final summary = await repo.importAll([
        entry(
          'a',
          '备份内容',
          createdAt: time.add(const Duration(days: 1)),
          updatedAt: time.add(const Duration(minutes: 1)),
        ),
      ]);
      expect(summary.updated, 1);
      final stored = (await repo.list()).single;
      expect(stored.content, '备份内容');
      expect(stored.createdAt, time);
      expect(stored.dayKey, '2026-10-28');
    },
  );

  test('an older backup entry never overwrites a newer local entry', () async {
    await repo.save(
      entry('a', '本机较新', updatedAt: time.add(const Duration(minutes: 10))),
    );
    final summary = await repo.importAll([entry('a', '备份较旧', updatedAt: time)]);
    expect(summary.skipped, 1);
    expect((await repo.list()).single.content, '本机较新');
  });

  test(
    'importing the same backup twice changes nothing the second time',
    () async {
      final backup = [
        entry('a', '第一条', updatedAt: time.add(const Duration(minutes: 1))),
        entry('b', '第二条', updatedAt: time.add(const Duration(minutes: 2))),
      ];
      final first = await repo.importAll(backup);
      expect(first.inserted, 2);
      final second = await repo.importAll(backup);
      expect(second.inserted, 0);
      expect(second.updated, 0);
      expect(second.skipped, 2);
      expect(await repo.list(), hasLength(2));
    },
  );

  test('a broken entry rolls the whole import back', () async {
    await repo.save(entry('keep', '保留这条'));
    await expectLater(
      repo.importAll([entry('new', '会被回滚'), entry('', '缺少 ID')]),
      throwsArgumentError,
    );
    final stored = await repo.list();
    expect(stored, hasLength(1));
    expect(stored.single.id, 'keep');
  });
}
