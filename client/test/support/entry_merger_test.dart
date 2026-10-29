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

  test('the merge compares update times at millisecond precision', () {
    final store = <String, Entry>{'a': entry('a')};
    final summary = mergeEntries(store, [
      entry('a', updatedAt: time.add(const Duration(microseconds: 500))),
    ]);
    expect(summary.skipped, 1);
    expect(summary.updated, 0);
    expect(store['a']!.updatedAt, time);
  });
}
