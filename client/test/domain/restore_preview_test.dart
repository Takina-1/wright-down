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
    expect(preview.updated, 1);
    expect(preview.skipped, 0);
  });

  test('an older backup entry is counted as skipped', () {
    final preview = compareRestore(
      [entry('a', updatedAt: base.add(const Duration(minutes: 1)))],
      [entry('a', updatedAt: base)],
    );
    expect(preview.skipped, 1);
    expect(preview.updated, 0);
  });

  test('an identical entry is counted as skipped', () {
    final preview = compareRestore([entry('a')], [entry('a')]);
    expect(preview.skipped, 1);
  });
}
