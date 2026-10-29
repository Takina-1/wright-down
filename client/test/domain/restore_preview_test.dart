import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/restore_preview.dart';

void main() {
  final base = DateTime.utc(2026, 10, 28, 8);
  Entry entry(String id, {DateTime? updatedAt, String content = '正文'}) => Entry(
    id: id,
    content: content,
    createdAt: base,
    updatedAt: updatedAt ?? base,
    dayKey: '2026-10-28',
  );

  test('a new id is counted as an insertion', () {
    final preview = compareRestore(const [], [entry('a')]);
    expect(preview.inserted, 1);
    expect(preview.updated, 0);
    expect(preview.skipped, 0);
    expect(preview.total, 1);
  });

  test('a newer backup entry is counted as an update', () {
    final preview = compareRestore(
      [entry('a', updatedAt: base)],
      [entry('a', updatedAt: base.add(const Duration(minutes: 1)))],
    );
    expect(preview.total, 1);
    expect(preview.inserted, 0);
    expect(preview.updated, 1);
    expect(preview.skipped, 0);
  });

  test('an older backup entry is counted as skipped', () {
    final preview = compareRestore(
      [entry('a', updatedAt: base.add(const Duration(minutes: 1)))],
      [entry('a', updatedAt: base)],
    );
    expect(preview.total, 1);
    expect(preview.inserted, 0);
    expect(preview.updated, 0);
    expect(preview.skipped, 1);
  });

  test('an identical entry is counted as skipped', () {
    final preview = compareRestore([entry('a')], [entry('a')]);
    expect(preview.total, 1);
    expect(preview.inserted, 0);
    expect(preview.updated, 0);
    expect(preview.skipped, 1);
  });

  test('a mixed batch counts insertions, updates and skips separately', () {
    final preview = compareRestore(
      [
        entry('a', updatedAt: base),
        entry('b', updatedAt: base.add(const Duration(minutes: 1))),
      ],
      [
        entry('c', updatedAt: base),
        entry('a', updatedAt: base.add(const Duration(minutes: 1))),
        entry('b', updatedAt: base),
      ],
    );
    expect(preview.total, 3);
    expect(preview.inserted, 1);
    expect(preview.updated, 1);
    expect(preview.skipped, 1);
  });

  test('a sub-millisecond newer backup entry is skipped like the store does', () {
    // 与 SQLite 存储层一致：只比较毫秒，同一毫秒内的时间戳一律跳过。
    final subMillisecond = DateTime.utc(2026, 10, 28, 8, 0, 0, 0, 500);
    expect(subMillisecond.millisecondsSinceEpoch, base.millisecondsSinceEpoch);
    final preview = compareRestore(
      [entry('a', updatedAt: base)],
      [entry('a', updatedAt: subMillisecond)],
    );
    expect(preview.total, 1);
    expect(preview.inserted, 0);
    expect(preview.updated, 0);
    expect(preview.skipped, 1);
  });
}
