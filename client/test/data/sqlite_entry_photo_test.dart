import 'dart:io';
import 'dart:typed_data';

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

void main() {
  setUpAll(sqfliteFfiInit);

  Entry entry(String id, String content,
      {Uint8List? photo, DateTime? updated}) => Entry(
    id: id,
    content: content,
    createdAt: DateTime.utc(2026, 10, 30, 2, 0),
    updatedAt: updated ?? DateTime.utc(2026, 10, 30, 2, 0),
    dayKey: '2026-10-30',
    photo: photo,
  );

  test('v5 库的 entries 表含 photo 列', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_photo_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    // 触发 onCreate（全新库直接建 v5 结构）。
    await repo.save(entry('a', '正文'));
    await repo.close();

    // 直接查底层 schema，绕开 _toEntry 的 photo 解码，钉住列的存在。
    final db = await factory.openDatabase(path, options: OpenDatabaseOptions());
    addTearDown(db.close);
    final columns = await db.rawQuery('PRAGMA table_info(entries)');
    expect(
      columns.map((row) => row['name']),
      contains('photo'),
      reason: '新建的 v5 库必须有 photo 列',
    );
  });

  test('AC-07: v4 库升级到 v5 后老数据完好且新增 photo 列', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_photo_');
    final path = '${temp.path}/journal.db';

    // 先手工建一个 v4 库（有 tags 列、无 photo 列、user_version=4）。
    final legacy = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE entries (
            id TEXT PRIMARY KEY NOT NULL,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            day_key TEXT NOT NULL,
            deleted_at INTEGER,
            mood TEXT,
            tags TEXT
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
      'id': 'legacy-photo-1',
      'content': '升级前写下的记录',
      'created_at': DateTime.utc(2026, 10, 28).millisecondsSinceEpoch,
      'updated_at': DateTime.utc(2026, 10, 28).millisecondsSinceEpoch,
      'day_key': '2026-10-28',
    });
    await legacy.close();

    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    // 触发 onUpgrade(4→5)。
    final entries = await repo.exportAll();
    expect(entries, hasLength(1));
    expect(entries.single.content, '升级前写下的记录');
    // 老行无照片：读回 null。
    expect(entries.single.photo, isNull);
    await repo.close();

    // 确认 schema 真的升到 v5：entries 表多了 photo 列。
    final db = await factory.openDatabase(path, options: OpenDatabaseOptions());
    addTearDown(db.close);
    final columns = await db.rawQuery('PRAGMA table_info(entries)');
    expect(
      columns.map((row) => row['name']),
      contains('photo'),
      reason: 'v4 升级到 v5 后 entries 表必须有 photo 列',
    );
  });

  test('AC-08: save 带 photo 后 list 与 exportAll 能读回', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_photo_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    final bytes = Uint8List.fromList([1, 2, 3, 255, 0, 128]);
    await repo.save(entry('p1', '带照片的记录', photo: bytes));
    final readBack = (await repo.list()).single.photo;
    expect(readBack, isNotNull);
    expect(readBack!.length, 6);
    for (var i = 0; i < bytes.length; i++) {
      expect(readBack[i], bytes[i]);
    }
    expect((await repo.exportAll()).single.photo, isNotNull);
  });

  test('AC-02: save 同 id 带 photo=null 能清除已有照片', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_photo_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    await repo.save(entry('p2', '先有照片', photo: Uint8List.fromList([1, 2, 3])));
    // always-write 口径：photo=null 即清除库中已有照片。
    await repo.save(
      entry('p2', '清除照片', photo: null,
          updated: DateTime.utc(2026, 10, 30, 3, 0)),
    );
    expect((await repo.list()).single.photo, isNull);
  });

  test('无照片时 photo 读回 null', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_photo_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    await repo.save(entry('p3', '无照片'));
    expect((await repo.list()).single.photo, isNull);
  });
}
