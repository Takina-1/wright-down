import 'dart:math';

import 'entry.dart';

/// 从一组未删除条目里随机抽一条。
///
/// [entries] 可以是含已删除条目的混合集合：内部先过滤掉 `isDeleted`，
/// 只在存活条目里抽，已删除条目不会被抽中（AC-06）。
///
/// [excludeId] 传入时要排除的条目 ID：直接从存活集里剔除该 ID 的条目后再抽，
/// 保证不会抽中它。用于「换一篇」——排除当前展示的那条，必然换到不同的
/// （AC-03）。按 ID 而非引用比较：调用方每次从仓储取到的都是新实例，
/// 用引用比较会失效（同一记录两次取出是不同对象）。剔除后存活集为空时返回 null。
///
/// 空集（或全部已删除）返回 `null`，不抛异常。
///
/// [random] 用于测试注入固定种子的 [Random]，生产调用方不传即取系统随机源。
Entry? pickRandomEntry(
  List<Entry> entries, {
  Random? random,
  String? excludeId,
}) {
  var live = entries.where((e) => !e.isDeleted).toList(growable: false);
  if (excludeId != null) {
    live = live.where((e) => e.id != excludeId).toList(growable: false);
  }
  if (live.isEmpty) return null;
  final rng = random ?? Random();
  final index = rng.nextInt(live.length);
  return live[index];
}
