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
  Entry entry(String id, String text, {DateTime? created}) => Entry(
    id: id,
    content: text,
    createdAt: created ?? time,
    updatedAt: time,
    dayKey: '2026-10-28',
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('local_diary_test_');
    repo = SqliteEntryRepository(
      factory: databaseFactoryFfi,
      path: '${temp.path}/journal.db',
    );
  });
  tearDown(() async {
    await repo.close();
    await temp.delete(recursive: true);
  });

  test('saved Chinese text survives a database close and reopen', () async {
    try {
      await repo.save(entry('a', '今天走了很远。\n明天继续 🌿'));
    } on UnimplementedError {
      fail('Local persistence has not been implemented');
    }
    await repo.close();
    repo = SqliteEntryRepository(
      factory: databaseFactoryFfi,
      path: '${temp.path}/journal.db',
    );
    final rows = await repo.list();
    expect(rows.single.content, '今天走了很远。\n明天继续 🌿');
    expect(rows.single.dayKey, '2026-10-28');
    expect(rows.single.createdAt, time);
  });

  test(
    'saving the same id updates one row and preserves creation time',
    () async {
      await repo.save(entry('a', 'first'));
      await repo.save(
        Entry(
          id: 'a',
          content: 'second',
          createdAt: time,
          updatedAt: time.add(const Duration(seconds: 5)),
          dayKey: '2026-10-28',
        ),
      );
      final rows = await repo.list();
      expect(rows, hasLength(1));
      expect(rows.single.content, 'second');
      expect(rows.single.createdAt, time);
      expect(rows.single.updatedAt, time.add(const Duration(seconds: 5)));
    },
  );

  test(
    'keyset pagination handles equal timestamps without duplicates',
    () async {
      for (final id in ['a', 'b', 'c', 'd', 'e']) {
        await repo.save(entry(id, id));
      }
      final first = await repo.list(limit: 2);
      final second = await repo.list(
        before: EntryCursor(first.last.createdAt, first.last.id),
        limit: 2,
      );
      final third = await repo.list(
        before: EntryCursor(second.last.createdAt, second.last.id),
        limit: 2,
      );
      expect([...first, ...second, ...third].map((e) => e.id), [
        'e',
        'd',
        'c',
        'b',
        'a',
      ]);
    },
  );

  test('invalid empty entries do not overwrite persisted content', () async {
    await repo.save(entry('a', 'keep me'));
    await expectLater(repo.save(entry('a', '  \n')), throwsArgumentError);
    expect((await repo.list()).single.content, 'keep me');
  });
}
