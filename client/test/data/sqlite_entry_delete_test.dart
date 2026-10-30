import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late SqliteEntryRepository repo;
  final time = DateTime.utc(2026, 10, 28, 8);

  Entry entry(String id, String content, {DateTime? created}) => Entry(
    id: id,
    content: content,
    createdAt: created ?? time,
    updatedAt: time,
    dayKey: '2026-10-28',
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('local_diary_delete_');
    repo = SqliteEntryRepository(
      factory: databaseFactoryFfi,
      path: '${temp.path}/journal.db',
    );
  });

  tearDown(() async {
    await repo.close();
    Object? cleanupError;
    try {
      await temp.delete(recursive: true);
    } catch (error) {
      // Windows 上偶发文件句柄占用，删不掉就留下路径，便于手工清理。
      debugPrint('删除临时目录失败: ${temp.path} ($error)');
      cleanupError = error;
    }
    // 清理失败不能被静默吞掉：断言无异常，测试要红，否则临时目录会一直堆积。
    expect(cleanupError, isNull, reason: '临时目录清理失败: ${temp.path}');
  });

  test('软删除后时间轴不再返回该条目，但导出仍能拿到删除标记', () async {
    await repo.save(entry('a', '正文'));
    await repo.softDelete('a');

    expect(await repo.list(), isEmpty);
    final exported = await repo.exportAll();
    expect(exported, hasLength(1));
    expect(exported.single.deletedAt, isNotNull);
    expect(exported.single.isDeleted, isTrue);
    // 正文与创建时间不受删除操作影响。
    expect(exported.single.content, '正文');
    expect(exported.single.createdAt, time);
  });

  test('回收站只列出已删除条目', () async {
    await repo.save(entry('a', '正文 a'));
    await repo.save(entry('b', '正文 b'));
    await repo.softDelete('b');

    final trash = await repo.listDeleted();
    expect(trash.map((e) => e.id), ['b']);
  });

  test('回收站按删除时间倒序排列', () async {
    await repo.save(entry('a', '正文 a'));
    await repo.save(entry('b', '正文 b'));
    await repo.save(entry('c', '正文 c'));

    await repo.softDelete('b');
    // 删除时间取的是当前时刻（毫秒精度），等一小段时间才能拉开顺序。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.softDelete('c');

    final trash = await repo.listDeleted();
    expect(trash.map((e) => e.id), ['c', 'b']);
    expect(
      trash.first.deletedAt!.millisecondsSinceEpoch,
      greaterThanOrEqualTo(trash.last.deletedAt!.millisecondsSinceEpoch),
    );
  });

  test('恢复后条目回到时间轴且创建时间不变', () async {
    await repo.save(entry('a', '正文'));
    final before = (await repo.exportAll()).single;
    await repo.softDelete('a');
    await repo.restore('a');

    final after = (await repo.list()).single;
    expect(after.id, 'a');
    expect(after.content, before.content);
    expect(after.createdAt, before.createdAt);
    expect(after.deletedAt, isNull);
    expect(after.isDeleted, isFalse);
    // 恢复后回收站里不该再出现它。
    expect(await repo.listDeleted(), isEmpty);
  });

  test('彻底删除后条目不再存在', () async {
    await repo.save(entry('a', '正文'));
    await repo.softDelete('a');
    await repo.purge('a');

    expect(await repo.exportAll(), isEmpty);
    expect(await repo.listDeleted(), isEmpty);
  });

  test('清空回收站只清掉已删除条目', () async {
    await repo.save(entry('a', '正文 a'));
    await repo.save(entry('b', '正文 b'));
    await repo.softDelete('b');

    expect(await repo.purgeAll(), 1);
    expect(await repo.listDeleted(), isEmpty);
    expect((await repo.list()).single.id, 'a');
  });

  test('对不存在的条目操作会抛错', () async {
    await expectLater(repo.softDelete('nope'), throwsStateError);
    await expectLater(repo.purge('nope'), throwsStateError);
  });

  test('恢复一个未删除的条目会抛错', () async {
    await repo.save(entry('a', '正文'));
    await expectLater(repo.restore('a'), throwsStateError);
  });

  test('恢复不存在的条目会抛错', () async {
    await expectLater(repo.restore('nope'), throwsStateError);
  });

  test('已删除的条目不会出现在分页结果里', () async {
    for (final id in ['a', 'b', 'c']) {
      await repo.save(entry(id, '正文 $id'));
    }
    await repo.softDelete('b');

    final first = await repo.list(limit: 10);
    expect(first.map((e) => e.id), isNot(contains('b')));

    final page = await repo.list(before: EntryCursor(time, 'c'), limit: 10);
    expect(page.map((e) => e.id), isNot(contains('b')));
  });

  test('对已删除条目重复软删除会刷新删除时间', () async {
    await repo.save(entry('a', '正文'));
    await repo.softDelete('a');
    final first = (await repo.exportAll()).single.deletedAt!;

    // 删除时间取当前时刻（毫秒精度），等一小段时间才能拉开顺序。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.softDelete('a');

    final second = (await repo.exportAll()).single.deletedAt!;
    expect(
      second.millisecondsSinceEpoch,
      greaterThan(first.millisecondsSinceEpoch),
    );
    // 条目仍在回收站里。
    expect((await repo.listDeleted()).map((e) => e.id), ['a']);
  });

  test('恢复会覆盖 updated_at，且版本戳只增不减', () async {
    await repo.save(entry('a', '正文'));
    final before = (await repo.exportAll()).single;
    await repo.softDelete('a');
    final deletedStamp = (await repo.exportAll()).single.updatedAt;

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.restore('a');

    final after = (await repo.exportAll()).single;
    expect(
      after.updatedAt.millisecondsSinceEpoch,
      greaterThanOrEqualTo(deletedStamp.millisecondsSinceEpoch),
    );
    expect(
      after.updatedAt.millisecondsSinceEpoch,
      greaterThanOrEqualTo(before.updatedAt.millisecondsSinceEpoch),
    );
  });

  test('版本戳只增不减：条目时间戳晚于当前时刻时不写小', () async {
    // 模拟设备时钟回拨：条目已有的版本戳比“现在”还新。
    final future = DateTime.now().toUtc().add(const Duration(days: 1));
    await repo.save(
      Entry(
        id: 'a',
        content: '正文',
        createdAt: time,
        updatedAt: future,
        dayKey: '2026-10-28',
      ),
    );

    await repo.softDelete('a');
    var current = (await repo.exportAll()).single;
    expect(
      current.updatedAt.millisecondsSinceEpoch,
      greaterThanOrEqualTo(future.millisecondsSinceEpoch),
    );

    await repo.restore('a');
    current = (await repo.exportAll()).single;
    expect(
      current.updatedAt.millisecondsSinceEpoch,
      greaterThanOrEqualTo(future.millisecondsSinceEpoch),
    );
  });

  test('编辑已删除的条目不会把它复活', () async {
    await repo.save(entry('a', '正文'));
    await repo.softDelete('a');

    // 编辑器构造的 Entry 不带 deletedAt。
    await repo.save(
      Entry(
        id: 'a',
        content: '改过的正文',
        createdAt: time,
        updatedAt: DateTime.now().toUtc(),
        dayKey: '2026-10-28',
      ),
    );

    final exported = (await repo.exportAll()).single;
    expect(exported.deletedAt, isNotNull);
    expect(exported.isDeleted, isTrue);
    expect(exported.content, '改过的正文');
    expect(await repo.list(), isEmpty);
    expect((await repo.listDeleted()).map((e) => e.id), ['a']);
  });

  test('回收站遵守 limit 上限', () async {
    await repo.save(entry('a', '正文 a'));
    await repo.save(entry('b', '正文 b'));
    await repo.softDelete('a');
    await repo.softDelete('b');

    final trash = await repo.listDeleted(limit: 1);

    expect(trash, hasLength(1));
    expect(trash.single.id, 'b');
  });

  test('彻底删除未删除的条目会抛错', () async {
    await repo.save(entry('a', '正文'));

    await expectLater(repo.purge('a'), throwsStateError);

    // 条目还在，没被误删。
    expect((await repo.exportAll()).map((e) => e.id), ['a']);
  });

  test('save 带上删除标记时按传入的写', () async {
    await repo.save(
      Entry(
        id: 'a',
        content: '正文',
        createdAt: time,
        updatedAt: time,
        dayKey: '2026-10-28',
        deletedAt: DateTime.utc(2026, 10, 30, 9),
      ),
    );

    final exported = (await repo.exportAll()).single;
    expect(exported.deletedAt, DateTime.utc(2026, 10, 30, 9));
    expect(await repo.list(), isEmpty);
    expect((await repo.listDeleted()).map((e) => e.id), ['a']);
  });
}
