/// 同步字段模型。每个可变字段独立携带版本戳（毫秒），做字段级 LWW。
///
/// 字段取值类型（由 field 名约定，协议层不强制）：
/// - content: String
/// - mood: String?（null 表示无心情）
/// - tags: List<String>
/// - dayKey: String
/// - deletedAt: int?（毫秒；null 表示未删除）
/// - photo: String?（OSS key；null 表示无照片）
class FieldValue {
  const FieldValue(this.v, this.t);

  final Object? v;
  final int t;

  @override
  bool operator ==(Object other) =>
      other is FieldValue && other.v == v && other.t == t;

  @override
  int get hashCode => Object.hash(v, t);
}

/// 同步用的条目：不可变的 id 与 createdAt + 字段级可变状态。
class SyncEntry {
  const SyncEntry({
    required this.id,
    required this.createdAt,
    required this.fields,
  });

  final String id;
  final int createdAt; // 毫秒；首次创建确定，同步不修改
  final Map<String, FieldValue> fields;
}
