import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';

import 'memory_repository.dart';

/// 可推进的固定时钟：起点与任务约定的固定时刻一致，需要多条不同删除时间时再前进。
class _FakeClock {
  _FakeClock([DateTime? start])
      : current = start ?? DateTime.utc(2026, 10, 30, 12);

  DateTime current;

  DateTime call() => current;

  void advance(Duration d) => current = current.add(d);
}

Entry _entry({
  required String id,
  String content = '正文',
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) {
  final created = createdAt ?? DateTime.utc(2026, 10, 28, 8);
  return Entry(
    id: id,
    content: content,
    createdAt: created,
    updatedAt: updatedAt ?? created,
    dayKey: '2026-10-28',
    deletedAt: deletedAt,
  );
}

void main() {
  group('MemoryRepository 删除语义', () {
    test('list 只返回未删除条目', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      await repo.save(_entry(id: 'a'));
      await repo.save(_entry(id: 'b', deletedAt: DateTime.utc(2026, 10, 30, 9)));

      final listed = await repo.list();

      expect(listed.map((e) => e.id), ['a']);
      expect(listed.every((e) => e.deletedAt == null), isTrue);
    });

    test('exportAll 返回全部条目含已删除条目', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      await repo.save(_entry(id: 'a'));
      await repo.save(_entry(id: 'b', deletedAt: DateTime.utc(2026, 10, 30, 9)));

      final exported = await repo.exportAll();

      expect(exported.map((e) => e.id).toSet(), {'a', 'b'});
      expect(exported.length, 2);
      expect(
        exported.where((e) => e.deletedAt != null).map((e) => e.id),
        ['b'],
      );
    });

    test('listDeleted 只返回已删除条目', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      await repo.save(_entry(id: 'a'));
      await repo.save(_entry(id: 'b', deletedAt: DateTime.utc(2026, 10, 30, 9)));

      final deleted = await repo.listDeleted();

      expect(deleted.map((e) => e.id), ['b']);
      expect(deleted.every((e) => e.deletedAt != null), isTrue);
    });

    test('listDeleted 按删除时间倒序排列', () async {
      final clock = _FakeClock();
      final repo = MemoryRepository(now: clock.call);
      await repo.save(_entry(id: 'first'));
      await repo.save(_entry(id: 'second'));

      await repo.softDelete('first');
      clock.advance(const Duration(days: 1));
      await repo.softDelete('second');

      final deleted = await repo.listDeleted();

      expect(deleted.map((e) => e.id), ['second', 'first']);
      expect(
        deleted.map((e) => e.deletedAt!.millisecondsSinceEpoch).toList(),
        [
          DateTime.utc(2026, 10, 31, 12).millisecondsSinceEpoch,
          DateTime.utc(2026, 10, 30, 12).millisecondsSinceEpoch,
        ],
      );
    });

    test('listDeleted 的排序只比较到毫秒精度', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      // 同一毫秒内的两个删除时间（只差微秒）：毫秒口径下二者等价，顺序只由 id 倒序决定。
      await repo.save(
        _entry(id: 'a', deletedAt: DateTime.utc(2026, 10, 30, 12, 0, 0, 0, 1)),
      );
      await repo.save(
        _entry(id: 'b', deletedAt: DateTime.utc(2026, 10, 30, 12, 0, 0, 0, 0)),
      );

      final deleted = await repo.listDeleted();

      expect(deleted.map((e) => e.id), ['b', 'a']);
    });

    test('listDeleted 遵守 limit 上限', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      await repo.save(_entry(id: 'a', deletedAt: DateTime.utc(2026, 10, 30, 9)));
      await repo.save(_entry(id: 'b', deletedAt: DateTime.utc(2026, 10, 30, 10)));

      final deleted = await repo.listDeleted(limit: 1);

      expect(deleted.map((e) => e.id), ['b']);
    });

    test('softDelete 写入删除时间并同步更新修改时间', () async {
      final stamp = DateTime.utc(2026, 10, 30, 12);
      final repo = MemoryRepository(now: () => stamp);
      await repo.save(_entry(id: 'a', updatedAt: DateTime.utc(2026, 10, 28, 8)));

      await repo.softDelete('a');

      final entry = repo.entries['a']!;
      expect(entry.deletedAt, stamp);
      expect(entry.deletedAt!.isUtc, isTrue);
      expect(entry.updatedAt, stamp);
      expect(entry.isDeleted, isTrue);
    });

    test('softDelete 把本地时间的时钟统一转成 UTC', () async {
      final local = DateTime(2026, 10, 30, 12);
      final repo = MemoryRepository(now: () => local);
      await repo.save(_entry(id: 'a'));

      await repo.softDelete('a');

      final entry = repo.entries['a']!;
      expect(entry.deletedAt!.isUtc, isTrue);
      expect(entry.updatedAt.isUtc, isTrue);
      // 与本地时刻指向同一瞬间，且统一成 UTC 表达。
      expect(entry.deletedAt, local.toUtc());
      expect(
        entry.deletedAt!.millisecondsSinceEpoch,
        local.millisecondsSinceEpoch,
      );

      await repo.restore('a');
      expect(repo.entries['a']!.updatedAt.isUtc, isTrue);
      expect(repo.entries['a']!.updatedAt, local.toUtc());
    });

    test('softDelete 失败时抛出且条目保持原样', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      final original = _entry(id: 'a', updatedAt: DateTime.utc(2026, 10, 28, 8));
      await repo.save(original);
      repo.failDelete = true;

      await expectLater(
        repo.softDelete('a'),
        throwsA(isA<StateError>()),
      );

      expect(repo.entries['a']!.deletedAt, isNull);
      expect(repo.entries['a']!.updatedAt, DateTime.utc(2026, 10, 28, 8));
      expect(repo.entries['a']!.content, original.content);
    });

    test('softDelete 对不存在的 ID 抛出 StateError', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      repo.failDelete = false;

      await expectLater(
        repo.softDelete('missing'),
        throwsA(isA<StateError>()),
      );
    });

    test('restore 清除删除标记并更新修改时间且保留正文与创建时间', () async {
      final clock = _FakeClock();
      final repo = MemoryRepository(now: clock.call);
      final created = DateTime.utc(2026, 10, 20, 9);
      await repo.save(
        _entry(id: 'a', content: '原始正文', createdAt: created),
      );
      await repo.softDelete('a');
      clock.advance(const Duration(hours: 5));

      await repo.restore('a');

      final entry = repo.entries['a']!;
      expect(entry.deletedAt, isNull);
      expect(entry.isDeleted, isFalse);
      expect(entry.updatedAt, DateTime.utc(2026, 10, 30, 17));
      expect(entry.content, '原始正文');
      expect(entry.createdAt, created);
    });

    test('restore 对未删除条目抛出 StateError', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      await repo.save(_entry(id: 'a'));

      await expectLater(
        repo.restore('a'),
        throwsA(isA<StateError>()),
      );
    });

    test('purge 彻底移除条目', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      await repo.save(_entry(id: 'a'));
      await repo.softDelete('a');

      await repo.purge('a');

      expect(repo.entries.containsKey('a'), isFalse);
      expect(await repo.listDeleted(), isEmpty);
    });

    test('purge 对不存在的 ID 抛出 StateError', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));

      await expectLater(
        repo.purge('missing'),
        throwsA(isA<StateError>()),
      );
    });

    test('purgeAll 只移除已删除条目并返回移除条数', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      await repo.save(_entry(id: 'a'));
      await repo.save(_entry(id: 'b'));
      await repo.save(_entry(id: 'c'));
      await repo.softDelete('b');
      await repo.softDelete('c');

      final removed = await repo.purgeAll();

      expect(removed, 2);
      expect(repo.entries.keys.toSet(), {'a'});
      expect((await repo.list()).map((e) => e.id), ['a']);
    });

    test('failListDeleted 命中时 listDeleted 抛出且不影响其他读取', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      await repo.save(_entry(id: 'a'));
      await repo.save(_entry(id: 'b', deletedAt: DateTime.utc(2026, 10, 30, 9)));
      repo.failListDeleted = true;

      await expectLater(
        repo.listDeleted(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'simulated read failure',
          ),
        ),
      );
      expect(await repo.list(), hasLength(1));
      expect(await repo.exportAll(), hasLength(2));
    });

    test('failList 与 failListDeleted 互不影响', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      await repo.save(_entry(id: 'b', deletedAt: DateTime.utc(2026, 10, 30, 9)));

      repo.failList = true;
      await expectLater(repo.list(), throwsA(isA<StateError>()));
      expect(await repo.listDeleted(), hasLength(1));

      repo.failList = false;
      repo.failListDeleted = true;
      await expectLater(repo.listDeleted(), throwsA(isA<StateError>()));
      expect(await repo.list(), isEmpty);
    });
  });

  group('MemoryRepository 与生产实现的口径一致', () {
    test('save 不会复活已删除条目', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      await repo.save(_entry(id: 'a'));
      await repo.softDelete('a');

      // 编辑器构造的 Entry 不带 deletedAt，保存不能把删除标记抹掉。
      await repo.save(_entry(id: 'a', content: '改过的正文'));

      final entry = repo.entries['a']!;
      expect(entry.deletedAt, DateTime.utc(2026, 10, 30, 12));
      expect(entry.content, '改过的正文');
      expect(await repo.list(), isEmpty);
      expect((await repo.listDeleted()).map((e) => e.id), ['a']);
    });

    test('save 带上 deletedAt 时按传入的写', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      await repo.save(_entry(id: 'a'));

      await repo.save(
        _entry(id: 'a', deletedAt: DateTime.utc(2026, 10, 30, 9)),
      );

      expect(repo.entries['a']!.deletedAt, DateTime.utc(2026, 10, 30, 9));
    });

    test('softDelete 对已删除条目重复调用会刷新删除时间', () async {
      final clock = _FakeClock();
      final repo = MemoryRepository(now: clock.call);
      await repo.save(_entry(id: 'a'));
      await repo.softDelete('a');
      final first = repo.entries['a']!.deletedAt!;

      clock.advance(const Duration(hours: 1));
      await repo.softDelete('a');

      expect(
        repo.entries['a']!.deletedAt!.millisecondsSinceEpoch,
        greaterThan(first.millisecondsSinceEpoch),
      );
    });

    test('restore 覆盖 updated_at 且时钟回拨时不倒退', () async {
      final clock = _FakeClock();
      final repo = MemoryRepository(now: clock.call);
      await repo.save(
        _entry(id: 'a', updatedAt: DateTime.utc(2026, 10, 28, 8)),
      );
      await repo.softDelete('a');
      final deletedStamp = repo.entries['a']!.updatedAt;

      clock.advance(const Duration(hours: 5));
      await repo.restore('a');
      expect(repo.entries['a']!.updatedAt.isAfter(deletedStamp), isTrue);

      // 时钟回拨到删除之前：版本戳只能不变，不能倒退。
      clock.current = DateTime.utc(2026, 10, 20, 9);
      await repo.softDelete('a');
      final beforeRestore = repo.entries['a']!.updatedAt;
      await repo.restore('a');
      expect(
        repo.entries['a']!.updatedAt.millisecondsSinceEpoch,
        greaterThanOrEqualTo(beforeRestore.millisecondsSinceEpoch),
      );
    });

    test('purge 未删除的条目抛出 StateError', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      await repo.save(_entry(id: 'a'));

      await expectLater(repo.purge('a'), throwsA(isA<StateError>()));

      expect(repo.entries.containsKey('a'), isTrue);
    });

    test('list 与 listDeleted 的 limit 小于 1 抛 ArgumentError', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      await repo.save(_entry(id: 'a'));

      await expectLater(repo.list(limit: 0), throwsArgumentError);
      await expectLater(repo.listDeleted(limit: 0), throwsArgumentError);
    });

    test('空 id 抛 ArgumentError', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));

      await expectLater(repo.softDelete(''), throwsArgumentError);
      await expectLater(repo.restore(''), throwsArgumentError);
      await expectLater(repo.purge(''), throwsArgumentError);
    });

    test('save 拒绝空正文且不写入条目', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));

      // 与生产实现一致：正文为空白也算空。
      await expectLater(
        repo.save(_entry(id: 'a', content: '   ')),
        throwsArgumentError,
      );

      expect(repo.entries.containsKey('a'), isFalse);
      expect(repo.saves, 0);
    });

    test('save 拒绝空 id 且不写入条目', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));

      await expectLater(repo.save(_entry(id: '')), throwsArgumentError);

      expect(repo.entries.containsKey(''), isFalse);
      expect(repo.entries, isEmpty);
      expect(repo.saves, 0);
    });

    test('restore 对不存在与未删除的条目抛同一条消息', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      await repo.save(_entry(id: 'a'));

      await expectLater(
        repo.restore('missing'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Entry missing is not in the trash',
          ),
        ),
      );
      await expectLater(
        repo.restore('a'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Entry a is not in the trash',
          ),
        ),
      );
    });

    test('list 的游标比较只到毫秒精度', () async {
      final repo = MemoryRepository(now: () => DateTime.utc(2026, 10, 30, 12));
      // 同一毫秒内的两个创建时间（只差微秒）：毫秒口径下二者等价。
      await repo.save(
        _entry(id: 'a', createdAt: DateTime.utc(2026, 10, 28, 8, 0, 0, 0, 1)),
      );
      await repo.save(
        _entry(id: 'b', createdAt: DateTime.utc(2026, 10, 28, 8, 0, 0, 0, 0)),
      );

      // 游标与 a 同毫秒：毫秒口径下 a 不早于游标，被排除；
      // b 与游标同毫秒但 id 更大，同样被排除。
      final page = await repo.list(
        before: EntryCursor(DateTime.utc(2026, 10, 28, 8, 0, 0, 0, 1), 'a'),
      );

      expect(page, isEmpty);
    });
  });
}
