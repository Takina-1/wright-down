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
      {String? mood, DateTime? updated}) => Entry(
    id: id, content: content,
    createdAt: DateTime.utc(2026, 10, 30, 2, 0),
    updatedAt: updated ?? DateTime.utc(2026, 10, 30, 2, 0),
    dayKey: '2026-10-30', mood: mood,
  );

  test('v3 库的 entries 表含 mood 列', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_mood_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    // 触发 onCreate（全新库直接建 v3 结构）。
    await repo.save(entry('a', '正文'));
    await repo.close();

    // _toEntry() 当前不读 mood（Task 3 才补），所以 Entry 层面的
    // 断言是恒真的——无论有没有 mood 列，mood 都是 null。必须绕开
    // _toEntry()，直接查底层 schema 才算钉住了列的存在。
    //
    // 校验打开不带 version：sqflite 在 oldVersion < version 且
    // onUpgrade == null 时不报错，只执行 setVersion，会悄悄改写
    // user_version，把校验本身变成一次写入。
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(),
    );
    addTearDown(db.close);
    final columns = await db.rawQuery('PRAGMA table_info(entries)');
    expect(
      columns.map((row) => row['name']),
      contains('mood'),
      reason: '新建的 v3 库必须有 mood 列',
    );
  });

  test('迁移幂等：v2 库升级到 v3 后老数据完好且新增 mood 列', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_mood_');
    final path = '${temp.path}/journal.db';

    // 先手工建一个 v2 库（有 deleted_at 列、无 mood 列、user_version=2），
    // 写入一条数据后关闭。这样再用 version 3 的 repository 打开才会真正
    // 触发 onUpgrade(2→3)，走 ALTER TABLE 加 mood 列的迁移路径——
    // 而不是像旧测试那样新建库走 onCreate 直接建 v3，迁移逻辑从未执行。
    final legacy = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE entries (
            id TEXT PRIMARY KEY NOT NULL,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            day_key TEXT NOT NULL,
            deleted_at INTEGER
          )''');
          // v2 库建表时带这三个索引；夹具必须补齐，否则迁移后的库
          // 与生产老库不一致。
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
      'id': 'legacy-1',
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

    // 用 version 3 的 repository 打开同一路径，触发 onUpgrade(2→3)。
    final entries = await repo.exportAll();
    expect(entries, hasLength(1));
    expect(entries.single.content, '升级前写下的记录');
    await repo.close();

    // 光断言「老数据没丢」不够：不迁移的库也能通过。必须确认 schema
    // 真的升到了 v3——entries 表多了 mood 列。
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(),
    );
    addTearDown(db.close);
    final columns = await db.rawQuery('PRAGMA table_info(entries)');
    expect(
      columns.map((row) => row['name']),
      contains('mood'),
      reason: 'v2 升级到 v3 后 entries 表必须有 mood 列',
    );
    // v2 的三个索引在迁移后必须保留。
    final indexes = await db.rawQuery('PRAGMA index_list(entries)');
    expect(
      indexes.map((row) => row['name']),
      containsAll(['entries_timeline', 'entries_day', 'entries_deleted']),
      reason: '迁移后必须保留 v2 的三个索引',
    );

    // 行级断言：老行的 mood 必须真的是 NULL。
    // Entry 层面断言是恒真的（_toEntry 还不读 mood），而 mood 列
    // 可空无默认值，ALTER TABLE 不会回填历史行——若迁移逻辑写错
    // （比如给老行塞了占位值），时间线上的条目会带着幽灵心情。
    final raw = await db.rawQuery(
      'SELECT mood FROM entries WHERE id = ?',
      ['legacy-1'],
    );
    expect(raw, hasLength(1));
    expect(
      raw.single['mood'],
      isNull,
      reason: '老行的 mood 必须为 NULL，不能是占位值',
    );
  });

  test('save 带 mood 后 list 与 exportAll 能读回', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_mood_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    await repo.save(entry('m1', '今天很开心', mood: 'happy'));
    expect((await repo.list()).single.mood, 'happy');
    expect((await repo.exportAll()).single.mood, 'happy');
  });

  test('mood 为空时列存 NULL，读回 null', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_mood_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    await repo.save(entry('m2', '没有心情'));
    expect((await repo.list()).single.mood, isNull);
  });

  test('AC-07: save 同 id 带 mood=null 能清除已有心情', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_mood_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    await repo.save(entry('m3', 'a', mood: 'happy'));
    // always-write 口径：编辑器总是携带当前 mood，mood=null 即清除库中
    // 已有的心情（AC-07）。不再沿用「非空才写」的旧口径。
    await repo.save(entry('m3', 'a 改', mood: null,
      updated: DateTime.utc(2026, 10, 30, 3, 0)));
    expect((await repo.list()).single.mood, isNull);
  });

  test('设置 mood 后清除，时间轴 list 与 exportAll 读回 null', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_mood_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    await repo.save(entry('m5', '今天很开心', mood: 'happy'));
    expect((await repo.list()).single.mood, 'happy');
    // 清除心情：always-write 口径下 save mood=null 即写 NULL，时间轴
    // list 与 exportAll 都应读回 null。
    await repo.save(entry('m5', '今天很开心', mood: null,
      updated: DateTime.utc(2026, 10, 30, 3, 0)));
    expect((await repo.list()).single.mood, isNull);
    expect((await repo.exportAll()).single.mood, isNull);
  });

  test('编辑带新 mood 的 Entry 会更新 mood', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_mood_');
    final path = '${temp.path}/journal.db';
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    await repo.save(entry('m4', 'a', mood: 'happy'));
    await repo.save(entry('m4', 'a 改', mood: 'sad',
      updated: DateTime.utc(2026, 10, 30, 3, 0)));
    expect((await repo.list()).single.mood, 'sad');
  });

  test('AC-09: 已含 mood 列的库（user_version=2）再次升级不报 duplicate column', () async {
    final factory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('local_diary_mood_');
    final path = '${temp.path}/journal.db';

    // 模拟用户用旧版打开过 v3 结构的库：表结构已含 mood 列，
    // 但 user_version 被旧版回退到 2。再用 version 3 的 repository
    // 打开会触发 onUpgrade(2→3)，迁移代码先查 PRAGMA table_info
    // 发现 mood 列已存在，跳过 ALTER——不报 duplicate column。
    final legacy = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          // 直接建 v3 结构（含 mood 列），但 user_version 是 2
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
      'id': 're-upgrade-1',
      'content': '旧版打开过的记录',
      'created_at': DateTime.utc(2026, 10, 28).millisecondsSinceEpoch,
      'updated_at': DateTime.utc(2026, 10, 28).millisecondsSinceEpoch,
      'day_key': '2026-10-28',
      'mood': 'happy',
    });
    await legacy.close();

    // 用 version 3 的 repository 打开同一路径，触发 onUpgrade(2→3)。
    // mood 列已存在，迁移代码应跳过 ALTER，不抛 duplicate column。
    final repo = SqliteEntryRepository(factory: factory, path: path);
    addTearDown(() async {
      await repo.close();
      await factory.deleteDatabase(path);
      await deleteTempDir(temp);
    });

    // 打开不抛异常即说明迁移幂等；数据完好且 mood 读回正确。
    final entries = await repo.exportAll();
    expect(entries, hasLength(1));
    expect(entries.single.content, '旧版打开过的记录');
    expect(entries.single.mood, 'happy');
  });
}
