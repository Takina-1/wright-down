import '../entry.dart';
import 'merge_decision.dart';

/// 导入前给用户看的合并结果预告。
class RestorePreview {
  const RestorePreview({
    required this.total,
    required this.inserted,
    required this.updated,
    required this.skipped,
  });

  /// 备份里的条目数，不是实际会写入本机的条数。
  final int total;
  final int inserted;
  final int updated;
  final int skipped;
}

/// 按 ID 与修改时间比较本地和备份，给出这次恢复会改动什么。
///
/// 判断规则由 [decideMerge] 统一提供，与仓储层的合并实现完全一致：
/// 预览的条数和实际导入的条数不会对不上。
///
/// 前置条件：[local] 必须包含本地已删除的条目。调用方要传入仓储的
/// `exportAll()` 结果（它不过滤已删除条目），否则预览会漏掉「本地已删除、
/// 备份未删除」这一条——预览说会更新，实际导入却会跳过，两边数字对不上。
RestorePreview compareRestore(List<Entry> local, List<Entry> incoming) {
  final byId = {for (final entry in local) entry.id: entry};
  var inserted = 0;
  var updated = 0;
  var skipped = 0;
  for (final entry in incoming) {
    switch (decideMerge(local: byId[entry.id], incoming: entry).action) {
      case MergeAction.insert:
        inserted++;
      case MergeAction.update:
        updated++;
      case MergeAction.skip:
        skipped++;
    }
  }
  return RestorePreview(
    total: incoming.length,
    inserted: inserted,
    updated: updated,
    skipped: skipped,
  );
}
