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
    expect(exported[20].id, 'id-19');
    expect(exported.last.id, 'id-00');
  });

  test('exportAll orders by creation time, not by id', () async {
    // 故意按最旧 → 最新的顺序写入：插入顺序与期望的创建时间倒序相反，
    // 这样夹具本身就能区分「按插入顺序排序」和「按创建时间排序」。
    await repo.save(entry('c', '最旧', createdAt: DateTime.utc(2026, 10, 26)));
    await repo.save(entry('b', '中间', createdAt: DateTime.utc(2026, 10, 27)));
    await repo.save(entry('a', '最新', createdAt: DateTime.utc(2026, 10, 28)));
    final exported = await repo.exportAll();
    expect(exported.map((e) => e.id).toList(), ['a', 'b', 'c']);
    expect(exported.first.id, 'a');
  });

  test('a new id from a backup is inserted', () async {
    final backupCreated = DateTime.utc(2026, 10, 25, 6, 30);
    final summary = await repo.importAll([
      entry(
        'a',
        '来自备份',
        createdAt: backupCreated,
        updatedAt: backupCreated,
        // 故意让 dayKey 与 createdAt 的本地日期不一致：
        // 这样断言 dayKey 只能来自备份，无法用 createdAt 重算出来蒙混过关。
        dayKey: '2026-03-08',
      ),
    ]);
    expect(summary.inserted, 1);
    expect(summary.updated, 0);
    expect(summary.skipped, 0);
    final stored = (await repo.list()).single;
    expect(stored.content, '来自备份');
    // 插入路径使用备份中的全部字段：ID、创建时间与 dayKey 都跟备份一致，
    // 不能用本地默认值，也不能沿用本机的日期分组。
    expect(stored.id, 'a');
    expect(stored.createdAt, backupCreated);
    expect(stored.updatedAt, backupCreated);
    expect(stored.dayKey, '2026-03-08');
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
    'a sub-millisecond newer backup entry is skipped, not applied',
    () async {
      await repo.save(entry('a', '本机内容', updatedAt: time));
      final summary = await repo.importAll([
        entry(
          'a',
          '备份内容',
          updatedAt: time.add(const Duration(microseconds: 500)),
        ),
      ]);
      expect(summary.updated, 0);
      expect(summary.skipped, 1);
      expect((await repo.list()).single.content, '本机内容');
    },
  );

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

  test(
    'an entry with a malformed day key rolls the whole import back',
    () async {
      await repo.save(entry('keep', '保留这条'));
      await expectLater(
        repo.importAll([
          entry('new', '会被回滚'),
          entry('bad', '日期键不合法', dayKey: '2026'),
        ]),
        throwsArgumentError,
      );
      final stored = await repo.list();
      expect(stored, hasLength(1));
      expect(stored.single.id, 'keep');
    },
  );

  test('本地已删除的条目不会被备份复活', () async {
    await repo.save(entry('a', '原本的正文'));
    await repo.softDelete('a');

    final incoming = Entry(
      id: 'a',
      content: '备份里的正文',
      createdAt: DateTime.utc(2026, 10, 28, 3),
      updatedAt: DateTime.utc(2026, 11, 1),
      dayKey: '2026-10-28',
    );
    final summary = await repo.importAll([incoming]);

    expect(summary.skipped, 1);
    expect(summary.updated, 0);
    expect(await repo.list(), isEmpty);
    expect((await repo.listDeleted()).single.content, '原本的正文');
  });

  test('备份里带删除标记的条目会把本地条目标记为已删除', () async {
    await repo.save(entry('a', '本机内容'));

    final incoming = Entry(
      id: 'a',
      content: '备份里的正文',
      createdAt: DateTime.utc(2026, 10, 28, 3),
      updatedAt: DateTime.utc(2026, 11, 1),
      dayKey: '2026-10-28',
      deletedAt: DateTime.utc(2026, 11, 1),
    );
    final summary = await repo.importAll([incoming]);

    expect(summary.updated, 1);
    expect(await repo.list(), isEmpty);
    expect((await repo.listDeleted()).single.id, 'a');
  });

  test('备份里的已删除条目插入后仍在回收站', () async {
    final incoming = Entry(
      id: 'a',
      content: '备份里的正文',
      createdAt: DateTime.utc(2026, 10, 28, 3),
      updatedAt: DateTime.utc(2026, 11, 1),
      dayKey: '2026-10-28',
      deletedAt: DateTime.utc(2026, 11, 1),
    );
    final summary = await repo.importAll([incoming]);

    expect(summary.inserted, 1);
    expect(await repo.list(), isEmpty);
    expect((await repo.listDeleted()).single.id, 'a');
  });
}
