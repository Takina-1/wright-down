import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';

import 'entry_merger.dart';

void main() {
  final time = DateTime.utc(2026, 10, 28, 8);

  Entry entry(String id, {DateTime? updatedAt}) => Entry(
    id: id,
    content: '内容 $id',
    createdAt: time,
    updatedAt: updatedAt ?? time,
    dayKey: '2026-10-28',
  );

  test('an entry without an id aborts the whole merge', () {
    final store = <String, Entry>{'keep': entry('keep')};
    expect(
      () => mergeEntries(store, [entry('new'), entry('')]),
      throwsArgumentError,
    );
    expect(store.keys, ['keep']);
  });

  test('a failed merge leaves an empty store untouched', () {
    final store = <String, Entry>{};
    expect(() => mergeEntries(store, [entry('')]), throwsArgumentError);
    expect(store, isEmpty);
  });

  test('an entry with a malformed day key aborts the whole merge', () {
    final store = <String, Entry>{'keep': entry('keep')};
    final bad = Entry(
      id: 'bad',
      content: '日期键不合法',
      createdAt: time,
      updatedAt: time,
      dayKey: '2026',
    );
    expect(() => mergeEntries(store, [entry('new'), bad]), throwsArgumentError);
    expect(store.keys, ['keep']);
  });

  test('the merge compares update times at millisecond precision', () {
    final store = <String, Entry>{'a': entry('a')};
    final summary = mergeEntries(store, [
      entry('a', updatedAt: time.add(const Duration(microseconds: 500))),
    ]);
    expect(summary.skipped, 1);
    expect(summary.updated, 0);
    expect(store['a']!.updatedAt, time);
  });

  test('本地已删除的条目不会被备份复活', () {
    final store = <String, Entry>{
      'a': Entry(
        id: 'a',
        content: '内容 a',
        createdAt: time,
        updatedAt: time,
        dayKey: '2026-10-28',
        deletedAt: time,
      ),
    };
    final summary = mergeEntries(store, [
      Entry(
        id: 'a',
        content: '备份里的内容',
        createdAt: time,
        updatedAt: time.add(const Duration(minutes: 5)),
        dayKey: '2026-10-28',
      ),
    ]);
    expect(summary.skipped, 1);
    expect(summary.updated, 0);
    // 仍是本地那条已删除的条目，正文没有被备份覆盖。
    expect(store['a']!.deletedAt, time);
    expect(store['a']!.content, '内容 a');
  });

  test('备份带删除标记时把本地条目标记为已删除', () {
    final store = <String, Entry>{'a': entry('a')};
    final deletedAt = time.add(const Duration(minutes: 5));
    final summary = mergeEntries(store, [
      Entry(
        id: 'a',
        content: '备份里的内容',
        createdAt: time,
        updatedAt: deletedAt,
        dayKey: '2026-10-28',
        deletedAt: deletedAt,
      ),
    ]);
    expect(summary.updated, 1);
    expect(store['a']!.deletedAt, deletedAt);
  });

  test('备份里的已删除条目插入后仍带删除标记', () {
    final store = <String, Entry>{};
    final deletedAt = time.add(const Duration(minutes: 5));
    final summary = mergeEntries(store, [
      Entry(
        id: 'a',
        content: '备份里的内容',
        createdAt: time,
        updatedAt: deletedAt,
        dayKey: '2026-10-28',
        deletedAt: deletedAt,
      ),
    ]);
    expect(summary.inserted, 1);
    expect(store['a']!.deletedAt, deletedAt);
  });
}
