import 'dart:math';

import 'entry.dart';

/// 从一组未删除条目里随机抽一条。
///
/// [entries] 可以是含已删除条目的混合集合：内部先过滤掉 `isDeleted`，
/// 只在存活条目里抽，已删除条目不会被抽中（AC-06）。
///
/// 空集（或全部已删除）返回 `null`，不抛异常。
///
/// [random] 用于测试注入固定种子的 [Random]，生产调用方不传即取系统随机源。
Entry? pickRandomEntry(List<Entry> entries, {Random? random}) {
  final live = entries.where((e) => !e.isDeleted).toList(growable: false);
  if (live.isEmpty) return null;
  final rng = random ?? Random();
  final index = rng.nextInt(live.length);
  return live[index];
}
