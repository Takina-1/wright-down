import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/domain/entry.dart';
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

Future<SqliteEntryRepository> _openMemory() async =>
    SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');

void main() {
  setUpAll(sqfliteFfiInit);

  test('photoKey 持久化与读回', () async {
    final repo = await _openMemory();
    final now = DateTime.now().toUtc();
    await repo.save(Entry(
      id: 'e1',
      content: 'x',
      createdAt: now,
      updatedAt: now,
      dayKey: '2026-11-03',
      photoKey: 'key-abc',
    ));
    final all = await repo.exportAll();
    expect(all.single.photoKey, 'key-abc');
    await repo.close();
  });

  test('photoKey 变化打 photo 时间戳', () async {
    final repo = await _openMemory();
    final t1 = DateTime.now().toUtc().millisecondsSinceEpoch;
    await repo.save(Entry(
      id: 'e1',
      content: 'x',
      createdAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
      dayKey: '2026-11-03',
    ));
    // 设 photoKey：photoKey 从 null 变 'key-1'，应打 'photo' 戳。
    final t2 = t1 + 1000;
    await repo.save(Entry(
      id: 'e1',
      content: 'x',
      createdAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(t2, isUtc: true),
      dayKey: '2026-11-03',
      photoKey: 'key-1',
    ));
    final all = await repo.exportAll();
    expect(all.single.syncStamps['photo'], greaterThan(0));
    // 未变更字段保留旧戳（正文没动，content 戳应不大于 t1）。
    expect(all.single.syncStamps['content'], lessThanOrEqualTo(t1));
    await repo.close();
  });

  test('photoKey 不变不打 photo 时间戳', () async {
    final repo = await _openMemory();
    final t1 = DateTime.now().toUtc().millisecondsSinceEpoch;
    await repo.save(Entry(
      id: 'e1',
      content: 'x',
      createdAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
      dayKey: '2026-11-03',
      photoKey: 'key-1',
    ));
    // 改正文，photoKey 不变：photo 戳应保留首次的，不被改正文覆盖。
    final t2 = t1 + 1000;
    await repo.save(Entry(
      id: 'e1',
      content: 'new',
      createdAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(t2, isUtc: true),
      dayKey: '2026-11-03',
      photoKey: 'key-1',
    ));
    final all = await repo.exportAll();
    // photoKey 没变，photo 戳应仍是首次的 t1（不被 t2 覆盖）。
    expect(all.single.syncStamps['photo'], lessThanOrEqualTo(t1));
    // 正文变了，content 戳更新到 t2。
    expect(all.single.syncStamps['content'], greaterThanOrEqualTo(t2));
    await repo.close();
  });

  test('saveMerged 持久化 photoKey', () async {
    final repo = await _openMemory();
    final now = DateTime.now().toUtc();
    // saveMerged 原样保留传入 syncStamps，但 photo_key 列必须落盘。
    await repo.saveMerged(Entry(
      id: 'e1',
      content: 'x',
      createdAt: now,
      updatedAt: now,
      dayKey: '2026-11-03',
      photoKey: 'key-merged',
    ));
    final all = await repo.exportAll();
    expect(all.single.photoKey, 'key-merged');
    await repo.close();
  });

  test('v6 库升级到 v7 后老数据完好且新增 photo_key 列', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_photokey_');
    final path = '${temp.path}/journal.db';

    // 先手工建一个 v6 库（有 sync_stamps 列、无 photo_key 列、user_version=6）。
    final legacy = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE entries (
            id TEXT PRIMARY KEY NOT NULL,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            day_key TEXT NOT NULL,
            deleted_at INTEGER,
            mood TEXT,
            tags TEXT,
            photo BLOB,
            sync_stamps TEXT
          )''');
          await db.execute(
            'CREATE INDEX entries_timeline ON entries(created_at DESC, id DESC)',
          );
          await db.execute('CREATE INDEX entries_day ON entries(day_key)');
          await db.execute(
            'CREATE INDEX entries_deleted ON entries(deleted_at DESC, id DESC)',
          );
        },
      ),
    );
    await legacy.insert('entries', {
      'id': 'legacy-photokey-1',
      'content': '升级前写下的记录',
      'created_at': DateTime.utc(2026, 10, 28).millisecondsSinceEpoch,
      'updated_at': DateTime.utc(2026, 10, 28).millisecondsSinceEpoch,
      'day_key': '2026-10-28',
      'sync_stamps': '{}',
    });
    await legacy.close();

    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    // 触发 onUpgrade(6→7)。
    final entries = await repo.exportAll();
    expect(entries, hasLength(1));
    expect(entries.single.content, '升级前写下的记录');
    // 老行无 photoKey：读回 null。
    expect(entries.single.photoKey, isNull);
    await repo.close();

    // 确认 schema 真的升到 v7：entries 表多了 photo_key 列。
    final db = await factory.openDatabase(path, options: OpenDatabaseOptions());
    addTearDown(db.close);
    final columns = await db.rawQuery('PRAGMA table_info(entries)');
    expect(
      columns.map((row) => row['name']),
      contains('photo_key'),
      reason: 'v6 升级到 v7 后 entries 表必须有 photo_key 列',
    );
  });

  test('全新建库时 entries 表含 photo_key 列', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_photokey_');
    final path = '${temp.path}/fresh.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    // 触发 onCreate（全新库直接建 v7 结构）。
    await repo.save(Entry(
      id: 'e1',
      content: 'x',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      dayKey: '2026-11-03',
      photoKey: 'key-fresh',
    ));
    await repo.close();

    // 直接查底层 schema，绕开 _toEntry 的 photoKey 解析，钉住列的存在。
    final db = await factory.openDatabase(path, options: OpenDatabaseOptions());
    addTearDown(db.close);
    final columns = await db.rawQuery('PRAGMA table_info(entries)');
    expect(
      columns.map((row) => row['name']),
      contains('photo_key'),
      reason: '新建的 v7 库必须有 photo_key 列',
    );
  });

  test('迁移幂等：user_version 被改回 6 后再升级也不会撞名', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_photokey_');
    final path = '${temp.path}/idempotent.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    // 先建出 v7 结构的库。
    await repo.save(Entry(
      id: 'e1',
      content: 'x',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      dayKey: '2026-11-03',
    ));
    await repo.close();

    // 模拟「用户用旧版打开过」：sqflite 在没有 onDowngrade 时只把
    // user_version 悄悄改回 6，表结构原样保留（含 photo_key 列）。
    final downgraded = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(),
    );
    await downgraded.execute('PRAGMA user_version = 6');
    await downgraded.close();

    // 再用 v7 打开：迁移会重跑，photo_key 列已经在了。
    // 不是幂等的话 ALTER TABLE 会抛 duplicate column name，
    // sqflite 会把异常抛出，整库再也打不开。
    final reopened = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(reopened.close);
    final entries = await reopened.exportAll();
    expect(entries, hasLength(1));

    final check = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(),
    );
    addTearDown(check.close);
    final columns = await check.rawQuery('PRAGMA table_info(entries)');
    expect(
      columns.map((row) => row['name']),
      contains('photo_key'),
      reason: '重跑 v7 迁移后 photo_key 列仍应存在且不冲突',
    );
  });
}
