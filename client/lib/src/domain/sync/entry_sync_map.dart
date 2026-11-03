import 'package:sync_core/sync_core.dart';

import '../entry.dart';

/// Entry → SyncEntry（推）：把 Entry 字段连同 syncStamps 组成字段级 patch。
/// 只输出 stamp > 0 的字段。
SyncEntry toSyncEntry(Entry e) {
  final fields = <String, FieldValue>{};
  void put(String name, Object? v, int stamp) {
    if (stamp > 0) fields[name] = FieldValue(v, stamp);
  }
  put('content', e.content, e.syncStamps['content'] ?? 0);
  put('mood', e.mood, e.syncStamps['mood'] ?? 0);
  put('tags', e.tags, e.syncStamps['tags'] ?? 0);
  put('deletedAt', e.deletedAt?.millisecondsSinceEpoch, e.syncStamps['deletedAt'] ?? 0);
  return SyncEntry(id: e.id, createdAt: e.createdAt.millisecondsSinceEpoch, fields: fields);
}

/// 拉：把远端 SyncEntry 字段级 LWW 合并入 local，更新 syncStamps。
/// 远端字段 t >= 本地戳才应用（平局取远端，即推送方）。
/// 逐字段用 if/else if 独立判断，避免 Dart switch 的 fallthrough 串扰。
Entry applyRemote(Entry local, SyncEntry remote) {
  final stamps = <String, int>{...local.syncStamps};

  String? content;
  String? mood = local.mood;
  List<String> tags = local.tags;
  int? deletedAt = local.deletedAt?.millisecondsSinceEpoch;

  for (final f in remote.fields.entries) {
    final t = f.value.t;
    if (f.key == 'content' && t >= (local.syncStamps['content'] ?? 0)) {
      content = f.value.v as String;
      stamps['content'] = t;
    } else if (f.key == 'mood' && t >= (local.syncStamps['mood'] ?? 0)) {
      mood = f.value.v as String?;
      stamps['mood'] = t;
    } else if (f.key == 'tags' && t >= (local.syncStamps['tags'] ?? 0)) {
      tags = (f.value.v as List).cast<String>();
      stamps['tags'] = t;
    } else if (f.key == 'deletedAt' && t >= (local.syncStamps['deletedAt'] ?? 0)) {
      deletedAt = f.value.v as int?;
      stamps['deletedAt'] = t;
    }
  }

  return Entry(
    id: local.id,
    content: content ?? local.content,
    createdAt: local.createdAt,
    updatedAt: local.updatedAt,
    dayKey: local.dayKey,
    deletedAt: deletedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(deletedAt, isUtc: true),
    mood: mood,
    tags: tags,
    photo: local.photo,
    syncStamps: stamps,
  );
}
