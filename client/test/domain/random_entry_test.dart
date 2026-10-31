import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/random_entry.dart';

void main() {
  Entry entry(String id, {String? content, DateTime? deletedAt}) => Entry(
        id: id,
        content: content ?? '$id 的正文',
        createdAt: DateTime.utc(2026, 10, 28, 8),
        updatedAt: DateTime.utc(2026, 10, 28, 8),
        dayKey: '2026-10-28',
        deletedAt: deletedAt,
      );

  test('AC-07: 空集合 → null', () {
    expect(pickRandomEntry([]), isNull);
  });

  test('AC-07: 全部已删除 → null', () {
    expect(
      pickRandomEntry([
        entry('a', deletedAt: DateTime.utc(2026, 10, 29)),
        entry('b', deletedAt: DateTime.utc(2026, 10, 29)),
      ]),
      isNull,
    );
  });

  test('AC-07: 单条 → 抽中它', () {
    final e = entry('only');
    expect(pickRandomEntry([e], random: Random(0)), e);
  });

  test('AC-07: 固定种子可复现（同种子同结果）', () {
    final list = [entry('a'), entry('b'), entry('c')];
    final first = pickRandomEntry(list, random: Random(42));
    final second = pickRandomEntry(list, random: Random(42));
    expect(first, same(second));
  });

  test('AC-06: 已删除条目不会被抽中', () {
    // 3 条：a 存活、b 已删、c 存活。无论 Random 取到哪个索引，
    // 抽中的都必须是 a 或 c（存活集），绝不可能是已删除的 b。
    final list = [
      entry('a'),
      entry('b', deletedAt: DateTime.utc(2026, 10, 29)),
      entry('c'),
    ];
    final picked = pickRandomEntry(list, random: Random(0));
    expect(picked, isNotNull);
    expect(picked!.isDeleted, isFalse);
    expect(['a', 'c'], contains(picked!.id));
  });

  test('多条时抽到的一定是集合内元素', () {
    final list = [entry('a'), entry('b'), entry('c'), entry('d')];
    final ids = <String>{};
    for (var seed = 0; seed < 20; seed++) {
      final picked = pickRandomEntry(list, random: Random(seed));
      expect(picked, isNotNull);
      ids.add(picked!.id);
    }
    // 多种子下应能覆盖到至少两条，证明确实是随机抽取而非固定第一条。
    expect(ids.length, greaterThan(1));
  });
}
