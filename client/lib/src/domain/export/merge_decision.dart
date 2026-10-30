import '../entry.dart';

/// 一条备份条目与本地条目合并后的处置。
enum MergeAction { insert, update, skip }

/// 合并判定结果。
class MergeDecision {
  const MergeDecision(this.action, this.entry);

  final MergeAction action;

  /// 合并后应当写入的条目。action 为 skip 时没有意义。
  final Entry entry;
}

/// 判定一条备份条目如何并入本地。
///
/// 预览（compareRestore）与实际导入（仓储层）必须调用这同一个函数，
/// 否则预告的条数和实际写入的条数会对不上。
///
/// 规则：
/// - 本地没有这条 → 插入。
/// - 本地已删除而备份未删除 → 跳过。本地删除优先，备份不能把它复活。
/// - 备份 updatedAt 更新 → 更新正文与删除状态；创建时间与 dayKey 以本地为准。
/// - 其余 → 跳过。
///
/// 时间比较按毫秒精度，与 SQLite 存储层一致。
MergeDecision decideMerge({Entry? local, required Entry incoming}) {
  if (local == null) {
    return MergeDecision(MergeAction.insert, incoming);
  }
  if (local.deletedAt != null && incoming.deletedAt == null) {
    return MergeDecision(MergeAction.skip, local);
  }
  if (incoming.updatedAt.millisecondsSinceEpoch >
      local.updatedAt.millisecondsSinceEpoch) {
    return MergeDecision(
      MergeAction.update,
      Entry(
        id: local.id,
        content: incoming.content,
        createdAt: local.createdAt,
        updatedAt: incoming.updatedAt,
        dayKey: local.dayKey,
        deletedAt: incoming.deletedAt,
      ),
    );
  }
  return MergeDecision(MergeAction.skip, local);
}
