import '../entry.dart';

/// 导入前给用户看的合并结果预告。
class RestorePreview {
  const RestorePreview({
    required this.total,
    required this.inserted,
    required this.updated,
    required this.skipped,
  });

  final int total;
  final int inserted;
  final int updated;
  final int skipped;
}

/// 按 ID 与修改时间比较本地和备份，给出这次恢复会改动什么。
/// 判断规则与仓储层的合并规则保持一致。
RestorePreview compareRestore(List<Entry> local, List<Entry> incoming) {
  final byId = {for (final entry in local) entry.id: entry};
  var inserted = 0;
  var updated = 0;
  var skipped = 0;
  for (final entry in incoming) {
    final existing = byId[entry.id];
    if (existing == null) {
      inserted++;
    } else if (entry.updatedAt.isAfter(existing.updatedAt)) {
      updated++;
    } else {
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
