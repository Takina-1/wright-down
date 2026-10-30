import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/import_summary.dart';
import 'package:local_diary/src/domain/export/merge_decision.dart';

/// 测试替身共用的合并实现。
///
/// 先整批校验并算出结果，全部通过后才一次性写入；任何一条出错就抛出，
/// 目标 map 保持原样——与生产实现的单事务回滚语义一致。
/// 判定规则与生产实现共用 [decideMerge]，包括「本地已删除不复活」。
ImportSummary mergeEntries(Map<String, Entry> store, List<Entry> incoming) {
  final pending = <String, Entry>{};
  var inserted = 0;
  var updated = 0;
  var skipped = 0;
  for (final entry in incoming) {
    if (entry.id.isEmpty) {
      throw ArgumentError('An imported entry needs an id');
    }
    // 与生产仓储一致：dayKey 不合法就整体拒绝导入。
    if (!isValidDayKey(entry.dayKey)) {
      throw ArgumentError('An imported entry needs a valid day key');
    }
    final existing = pending[entry.id] ?? store[entry.id];
    final decision = decideMerge(local: existing, incoming: entry);
    switch (decision.action) {
      case MergeAction.insert:
        // 写入的条目带上删除标记：备份里已删除的条目恢复后仍应留在回收站。
        pending[entry.id] = decision.entry;
        inserted++;
      case MergeAction.update:
        pending[entry.id] = decision.entry;
        updated++;
      case MergeAction.skip:
        skipped++;
    }
  }
  store.addAll(pending);
  return ImportSummary(inserted: inserted, updated: updated, skipped: skipped);
}
