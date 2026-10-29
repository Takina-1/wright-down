import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/import_summary.dart';

/// 测试替身共用的合并实现。
///
/// 先整批校验并算出结果，全部通过后才一次性写入；任何一条出错就抛出，
/// 目标 map 保持原样——与生产实现的单事务回滚语义一致。
/// 判定口径是毫秒精度，与 SQLite 实现和 compareRestore 一致。
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
    if (existing == null) {
      pending[entry.id] = entry;
      inserted++;
    } else if (entry.updatedAt.millisecondsSinceEpoch >
        existing.updatedAt.millisecondsSinceEpoch) {
      pending[entry.id] = Entry(
        id: existing.id,
        content: entry.content,
        createdAt: existing.createdAt,
        updatedAt: entry.updatedAt,
        dayKey: existing.dayKey,
      );
      updated++;
    } else {
      skipped++;
    }
  }
  store.addAll(pending);
  return ImportSummary(inserted: inserted, updated: updated, skipped: skipped);
}
