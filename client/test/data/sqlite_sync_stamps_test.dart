import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<SqliteEntryRepository> _open() async {
  return SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('sync_stamps 维护', () {
    test('新建条目所有字段打 now 时间戳', () async {
      final repo = await _open();
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await repo.save(Entry(
        id: 'e1', content: 'hi',
        createdAt: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
        dayKey: '2026-11-03', mood: 'happy', tags: ['a'],
      ));
      final all = await repo.exportAll();
      final stamps = all.single.syncStamps;
      expect(stamps['content'], greaterThanOrEqualTo(now));
      expect(stamps['mood'], greaterThanOrEqualTo(now));
      expect(stamps['tags'], greaterThanOrEqualTo(now));
      await repo.close();
    });

    test('只改字段时只打该字段时间戳', () async {
      final repo = await _open();
      final t1 = DateTime.now().toUtc().millisecondsSinceEpoch;
      await repo.save(Entry(
        id: 'e1', content: 'old',
        createdAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
        dayKey: '2026-11-03', mood: 'happy', tags: ['a'],
      ));
      // 改正文，心情/标签不变
      final t2 = t1 + 1000;
      await repo.save(Entry(
        id: 'e1', content: 'new',
        createdAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(t2, isUtc: true),
        dayKey: '2026-11-03', mood: 'happy', tags: ['a'],
      ));
      final all = await repo.exportAll();
      final stamps = all.single.syncStamps;
      expect(stamps['content'], greaterThanOrEqualTo(t2)); // 正文变了，更新
      expect(stamps['mood'], lessThan(t2)); // 心情没变，保留旧戳
      await repo.close();
    });

    test('软删除打 deletedAt 时间戳', () async {
      final repo = await _open();
      final t1 = DateTime.now().toUtc().millisecondsSinceEpoch;
      await repo.save(Entry(
        id: 'e1', content: 'x',
        createdAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
        dayKey: '2026-11-03',
      ));
      await repo.softDelete('e1');
      final all = await repo.exportAll();
      expect(all.single.syncStamps['deletedAt'], greaterThan(0));
      await repo.close();
    });

    test('恢复也打 deletedAt 时间戳', () async {
      final repo = await _open();
      final t1 = DateTime.now().toUtc().millisecondsSinceEpoch;
      await repo.save(Entry(
        id: 'e1', content: 'x',
        createdAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(t1, isUtc: true),
        dayKey: '2026-11-03',
      ));
      await repo.softDelete('e1');
      await repo.restore('e1');
      final all = await repo.exportAll();
      expect(all.single.syncStamps['deletedAt'], greaterThan(0));
      await repo.close();
    });
  });
}
