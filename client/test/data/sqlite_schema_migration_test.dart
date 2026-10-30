import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 清理临时目录：句柄尚未释放时删除会失败，不能静默吞掉，
/// 否则 Windows 上会悄悄留下残目录且无人知晓。
Future<void> deleteTempDir(Directory temp) async {
  try {
    await temp.delete(recursive: true);
  } on FileSystemException catch (error) {
    debugPrint('临时目录删除失败（句柄可能未释放）: ${temp.path} — $error');
  }
}

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
      await deleteTempDir(temp);
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
          // 真实 v1 库建表时还会带上这两个索引；夹具必须补齐，
          // 否则迁移后的库在测试里只剩 entries_deleted，与生产老库不一致。
          await db.execute(
            'CREATE INDEX entries_timeline ON entries(created_at DESC, id DESC)',
          );
          await db.execute('CREATE INDEX entries_day ON entries(day_key)');
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
    await repository.close();

    // 光断言「老数据没丢」不够：不迁移的库也能通过。
    // 必须确认 schema 真的升到了 v2：多出 deleted_at 列和 entries_deleted 索引。
    //
    // 校验打开不要带 version：sqflite 在 oldVersion < version 且
    // onUpgrade == null 时不报错，只执行 setVersion(2)，会悄悄改写
    // user_version，把校验本身变成一次写入。
    final migrated = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(),
    );
    addTearDown(migrated.close);
    final columns = await migrated.rawQuery('PRAGMA table_info(entries)');
    expect(
      columns.map((row) => row['name']),
      contains('deleted_at'),
      reason: '迁移后 entries 表必须有 deleted_at 列',
    );

    // 行级断言：老行的 deleted_at 必须真的是 NULL。
    // Entry 层面断言是恒真的（_toEntry 还不读 deleted_at），
    // 而 0 在语义上等于「已删除」，老记录会集体从时间轴上消失。
    // 所以绕开 _toEntry()，直接查原始行。
    final raw = await migrated.rawQuery(
      'SELECT deleted_at FROM entries WHERE id = ?',
      ['legacy-1'],
    );
    expect(raw, hasLength(1));
    expect(
      raw.single['deleted_at'],
      isNull,
      reason: '老行的 deleted_at 必须为 NULL，不能是 0',
    );

    final indexes = await migrated.rawQuery('PRAGMA index_list(entries)');
    expect(
      indexes.map((row) => row['name']),
      containsAll(['entries_timeline', 'entries_day', 'entries_deleted']),
      reason: '迁移后必须保留 v1 的两个索引并新增 entries_deleted',
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
      await deleteTempDir(temp);
    });

    // 触发 onCreate（而不是 onUpgrade）。
    await repository.exportAll();
    await repository.close();

    // 同样不带 version，避免校验打开时改写 user_version。
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(),
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

  test('迁移幂等：user_version 被旧版改回 1 后再升级也不会撞名', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp(
      'local_diary_idempotent_',
    );
    final path = '${temp.path}/idempotent.db';
    final repository = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repository.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    // 先建出 v2 结构的库。
    await repository.exportAll();
    await repository.close();

    // 模拟「用户用旧版打开过」：sqflite 在没有 onDowngrade 时只把
    // user_version 悄悄改回 1，表结构原样保留。
    final downgraded = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(),
    );
    await downgraded.execute('PRAGMA user_version = 1');
    await downgraded.close();

    // 再用 v2 打开：迁移会重跑，deleted_at 列已经在了。
    // 不是幂等的话 ALTER TABLE 会抛 duplicate column name，
    // sqflite 会把异常抛出，整库再也打不开。
    final reopened = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(reopened.close);
    final entries = await reopened.exportAll();
    expect(entries, isEmpty);

    final check = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(),
    );
    addTearDown(check.close);
    final columns = await check.rawQuery('PRAGMA table_info(entries)');
    expect(
      columns.map((row) => row['name']),
      contains('deleted_at'),
      reason: '重跑迁移后 deleted_at 列仍应存在且不冲突',
    );
    final indexes = await check.rawQuery('PRAGMA index_list(entries)');
    expect(
      indexes.map((row) => row['name']),
      containsAll(['entries_timeline', 'entries_day', 'entries_deleted']),
      reason: '重跑迁移后三个索引应齐全且不重复报错',
    );
  });
}
