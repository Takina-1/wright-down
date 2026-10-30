import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Entry _e(String id, {String? mood, DateTime? updated}) => Entry(
  id: id, content: 'c$id',
  createdAt: DateTime.utc(2026, 10, 30, 2, 0),
  updatedAt: updated ?? DateTime.utc(2026, 10, 30, 2, 0),
  dayKey: '2026-10-30', mood: mood,
);

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late SqliteEntryRepository repo;

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

  test('备份 updatedAt 更新且带 mood → 本地 mood 被覆盖', () async {
    await repo.save(_e('x', mood: 'happy', updated: DateTime.utc(2026, 10, 30, 2, 0)));
    await repo.importAll([_e('x', mood: 'sad', updated: DateTime.utc(2026, 10, 30, 9, 0))]);
    expect((await repo.list()).single.mood, 'sad');
  });

  test('备份 updatedAt 更新但不带 mood → 本地 mood 被清空', () async {
    await repo.save(_e('y', mood: 'happy', updated: DateTime.utc(2026, 10, 30, 2, 0)));
    await repo.importAll([_e('y', mood: null, updated: DateTime.utc(2026, 10, 30, 9, 0))]);
    expect((await repo.list()).single.mood, isNull);
  });

  test('备份 updatedAt 较旧 → 跳过，本地 mood 不变', () async {
    await repo.save(_e('z', mood: 'happy', updated: DateTime.utc(2026, 10, 30, 9, 0)));
    await repo.importAll([_e('z', mood: 'sad', updated: DateTime.utc(2026, 10, 30, 2, 0))]);
    expect((await repo.list()).single.mood, 'happy');
  });
}
