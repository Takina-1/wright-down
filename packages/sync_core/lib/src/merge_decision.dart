import 'entry_sync.dart';

/// 字段级 LWW：版本戳大的赢；相等取 incoming（推送方 / 服务端解析态）。
///
/// 客户端拉取合并与服务端推送合并共用本函数，保证两端冲突解决一致。
FieldValue mergeFieldLww(FieldValue existing, FieldValue incoming) {
  return incoming.t >= existing.t ? incoming : existing;
}

/// 把一条 SyncEntry 逐字段合并入本地字段状态，返回合并后的映射。
/// 本地没有的字段直接采用 incoming；已有字段走 [mergeFieldLww]。
Map<String, FieldValue> mergeSyncEntry(
  Map<String, FieldValue> local,
  SyncEntry incoming,
) {
  final merged = <String, FieldValue>{...local};
  for (final e in incoming.fields.entries) {
    final existing = local[e.key];
    merged[e.key] =
        existing == null ? e.value : mergeFieldLww(existing, e.value);
  }
  return merged;
}
