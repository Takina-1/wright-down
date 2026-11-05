/// 同步字段模型。每个可变字段独立携带版本戳（毫秒），做字段级 LWW。
///
/// 字段取值类型（由 field 名约定，协议层不强制）：
/// - content: String
/// - mood: String?（null 表示无心情）
/// - tags: List<String>
/// - dayKey: String
/// - deletedAt: int?（毫秒；null 表示未删除）
/// - photo: String?（COS key；null 表示无照片）
class FieldValue {
  const FieldValue(this.v, this.t);

  final Object? v;
  final int t;

  @override
  bool operator ==(Object other) {
    if (other is FieldValue && other.t == t) {
      return _valuesEqual(v, other.v);
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(v, t);

  /// 值比较：集合按内容深度比较，其余走 ==。
  /// SDK 的 List/Map/Set == 在某些运行时是恒等比较，故显式深度比较，
  /// 保证字段级同步的相等语义不依赖运行时实现。FieldValue 仅作 Map 值
  /// 使用（SyncEntry.fields 键为 String），hashCode 契约不影响。
  static bool _valuesEqual(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_valuesEqual(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final e in a.entries) {
        if (!b.containsKey(e.key)) return false;
        if (!_valuesEqual(e.value, b[e.key])) return false;
      }
      return true;
    }
    if (a is Set && b is Set) {
      if (a.length != b.length) return false;
      for (final x in a) {
        if (!b.contains(x)) return false;
      }
      return true;
    }
    return a == b;
  }
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
