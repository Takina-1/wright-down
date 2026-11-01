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

void main() {
  setUpAll(sqfliteFfiInit);

  Entry entry(String id, String content,
      {List<String> tags = const [], DateTime? updated}) => Entry(
    id: id,
    content: content,
    createdAt: DateTime.utc(2026, 10, 30, 2, 0),
    updatedAt: updated ?? DateTime.utc(2026, 10, 30, 2, 0),
    dayKey: '2026-10-30',
    tags: tags,
  );

  test('v4 库的 entries 表含 tags 列', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_tags_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    // 触发 onCreate（全新库直接建 v4 结构）。
    await repo.save(entry('a', '正文'));
    await repo.close();

    // 直接查底层 schema，绕开 _toEntry 的 tags 解码，钉住列的存在。
    final db = await factory.openDatabase(path, options: OpenDatabaseOptions());
    addTearDown(db.close);
    final columns = await db.rawQuery('PRAGMA table_info(entries)');
    expect(
      columns.map((row) => row['name']),
      contains('tags'),
      reason: '新建的 v4 库必须有 tags 列',
    );
  });

  test('AC-07: v3 库升级到 v4 后老数据完好且新增 tags 列', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_tags_');
    final path = '${temp.path}/journal.db';

    // 先手工建一个 v3 库（有 mood 列、无 tags 列、user_version=3）。
    final legacy = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE entries (
            id TEXT PRIMARY KEY NOT NULL,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            day_key TEXT NOT NULL,
            deleted_at INTEGER,
            mood TEXT
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
      'id': 'legacy-tags-1',
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

    // 触发 onUpgrade(3→4)。
    final entries = await repo.exportAll();
    expect(entries, hasLength(1));
    expect(entries.single.content, '升级前写下的记录');
    // 老行无标签：读回空列表（不是 null、不是占位值）。
    expect(entries.single.tags, isEmpty);
    await repo.close();

    // 确认 schema 真的升到 v4：entries 表多了 tags 列。
    final db = await factory.openDatabase(path, options: OpenDatabaseOptions());
    addTearDown(db.close);
    final columns = await db.rawQuery('PRAGMA table_info(entries)');
    expect(
      columns.map((row) => row['name']),
      contains('tags'),
      reason: 'v3 升级到 v4 后 entries 表必须有 tags 列',
    );
  });

  test('AC-08: save 带 tags 后 list 与 exportAll 能读回', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_tags_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    await repo.save(entry('t1', '带标签的记录', tags: ['旅行', '读书']));
    expect((await repo.list()).single.tags, ['旅行', '读书']);
    expect((await repo.exportAll()).single.tags, ['旅行', '读书']);
  });

  test('AC-03: list(tag:) 只返回带该标签的未删除条目', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_tags_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    // 给 a、b 不同的 created_at：时间轴按 created_at DESC，a 更新排前。
    await repo.save(
      Entry(
        id: 'a',
        content: '旅行记录',
        createdAt: DateTime.utc(2026, 10, 30, 3, 0),
        updatedAt: DateTime.utc(2026, 10, 30, 3, 0),
        dayKey: '2026-10-30',
        tags: ['旅行', '读书'],
      ),
    );
    await repo.save(
      Entry(
        id: 'b',
        content: '读书记录',
        createdAt: DateTime.utc(2026, 10, 30, 2, 0),
        updatedAt: DateTime.utc(2026, 10, 30, 2, 0),
        dayKey: '2026-10-30',
        tags: ['读书'],
      ),
    );
    await repo.save(entry('c', '无标签记录'));
    // 已删除的带标签条目不应被筛出来。
    await repo.save(
      Entry(
        id: 'd',
        content: '已删除的旅行',
        createdAt: DateTime.utc(2026, 10, 30, 1, 0),
        updatedAt: DateTime.utc(2026, 10, 30, 1, 0),
        dayKey: '2026-10-30',
        tags: ['旅行'],
        deletedAt: DateTime.utc(2026, 10, 31, 0, 0),
      ),
    );

    final travel = await repo.list(tag: '旅行');
    expect(travel.map((e) => e.id), ['a']);

    final reading = await repo.list(tag: '读书');
    expect(reading.map((e) => e.id), ['a', 'b']);
  });

  test('AC-03: 标签筛选大小写敏感（Travel 与 travel 不同）', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_tags_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    await repo.save(entry('a', '英文标签', tags: ['Travel']));
    expect((await repo.list(tag: 'Travel')).map((e) => e.id), ['a']);
    expect((await repo.list(tag: 'travel')), isEmpty);
  });

  test('AC-02: save 同 id 带空 tags 能清除已有标签', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_tags_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    await repo.save(entry('t2', '先有标签', tags: ['旅行']));
    // always-write 口径：空列表即清除库中已有标签。
    await repo.save(
      entry('t2', '清除标签', tags: const [],
          updated: DateTime.utc(2026, 10, 30, 3, 0)),
    );
    expect((await repo.list()).single.tags, isEmpty);
  });

  test('脏 tags（非 JSON）解码退回空列表，不让读崩', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_tags_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    await repo.save(entry('dirty', '脏标签数据', tags: ['旅行']));
    await repo.close();

    // 直接把 tags 列改成非 JSON 的脏值，模拟手工改过的库。
    final db = await factory.openDatabase(path, options: OpenDatabaseOptions());
    addTearDown(db.close);
    await db.update('entries', {'tags': '这不是 JSON'},
        where: 'id = ?', whereArgs: ['dirty']);
    await db.close();

    final repo2 = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(repo2.close);
    final entries = await repo2.list();
    expect(entries, hasLength(1));
    // 解码失败退回空列表，条目仍可显示。
    expect(entries.single.tags, isEmpty);
    expect(entries.single.content, '脏标签数据');
  });
}
