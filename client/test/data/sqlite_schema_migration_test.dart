import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('version 1 的库升级到 version 2 后老数据完好且删除标记为空', () async {
    final factory = databaseFactoryFfi;
    // 沿用既有集成测试的临时路径写法：测试库只存在于临时目录里，
    // 结束后整个目录删除，不在磁盘上留下残留。
    final temp = await Directory.systemTemp.createTemp(
      'local_diary_migration_',
    );
    final path = '${temp.path}/migration_test.db';
    final repository = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repository.close();
      await factory.deleteDatabase(path);
      try {
        await temp.delete(recursive: true);
      } on FileSystemException {
        // 句柄尚未释放时删除会失败；临时目录由系统自行回收。
      }
    });

    // 先按旧版本建库并写入数据。
    final legacy = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE entries (
            id TEXT PRIMARY KEY NOT NULL,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            day_key TEXT NOT NULL
          )''');
        },
      ),
    );
    await legacy.insert('entries', {
      'id': 'legacy-1',
      'content': '升级前写下的记录',
      'created_at': DateTime.utc(2026, 10, 28).millisecondsSinceEpoch,
      'updated_at': DateTime.utc(2026, 10, 28).millisecondsSinceEpoch,
      'day_key': '2026-10-28',
    });
    await legacy.close();

    final entries = await repository.exportAll();
    expect(entries, hasLength(1));
    expect(entries.single.content, '升级前写下的记录');
    expect(entries.single.deletedAt, isNull);
    await repository.close();

    // 光断言「老数据没丢」不够：不迁移的库也能通过。
    // 必须确认 schema 真的升到了 v2：多出 deleted_at 列和 entries_deleted 索引。
    final migrated = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 2),
    );
    addTearDown(migrated.close);
    final columns = await migrated.rawQuery('PRAGMA table_info(entries)');
    expect(
      columns.map((row) => row['name']),
      contains('deleted_at'),
      reason: '迁移后 entries 表必须有 deleted_at 列',
    );
    final indexes = await migrated.rawQuery('PRAGMA index_list(entries)');
    expect(
      indexes.map((row) => row['name']),
      contains('entries_deleted'),
      reason: '迁移后必须建出 entries_deleted 索引',
    );
  });

  test('全新建库时也带上 deleted_at 列和 entries_deleted 索引', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp(
      'local_diary_schema_',
    );
    final path = '${temp.path}/fresh.db';
    final repository = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repository.close();
      await factory.deleteDatabase(path);
      try {
        await temp.delete(recursive: true);
      } on FileSystemException {
        // 句柄尚未释放时删除会失败；临时目录由系统自行回收。
      }
    });

    // 触发 onCreate（而不是 onUpgrade）。
    await repository.exportAll();
    await repository.close();

    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 2),
    );
    addTearDown(db.close);
    final columns = await db.rawQuery('PRAGMA table_info(entries)');
    expect(
      columns.map((row) => row['name']),
      contains('deleted_at'),
      reason: '新建的库也必须有 deleted_at 列',
    );
    final indexes = await db.rawQuery('PRAGMA index_list(entries)');
    expect(
      indexes.map((row) => row['name']),
      containsAll(['entries_timeline', 'entries_day', 'entries_deleted']),
      reason: '新建的库必须建出全部三个索引',
    );
  });
}
