import 'dart:convert';

import 'entry_sync.dart';

/// 游标：0 表示从最早开始。
typedef Cursor = int;

/// 服务端返回的拉取结果。cursor = 本次结果最大 seq，下次请求带上。
class SyncPullResponse {
  const SyncPullResponse({required this.cursor, required this.entries});
  final int cursor;
  final List<SyncEntry> entries;

  Map<String, dynamic> toJson() => {
        'cursor': cursor,
        'entries': entries.map((e) => _entryToJson(e)).toList(),
      };

  static SyncPullResponse fromJson(Map<String, dynamic> j) => SyncPullResponse(
        cursor: j['cursor'] as int,
        entries: (j['entries'] as List)
            .map((e) => _entryFromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 客户端推送的单条条目变更（仅变更字段，每字段带版本戳）。
class EntryPatch {
  const EntryPatch({
    required this.id,
    required this.createdAt,
    required this.fields,
  });
  final String id;
  final int createdAt;
  final Map<String, FieldValue> fields;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt,
        'fields': fields.map((k, v) => MapEntry(k, _fieldToJson(v))),
      };

  static EntryPatch fromJson(Map<String, dynamic> j) => EntryPatch(
        id: j['id'] as String,
        createdAt: j['createdAt'] as int,
        fields: (j['fields'] as Map).map(
            (k, v) => MapEntry(k as String, _fieldFromJson(v as Map<String, dynamic>))),
      );
}

/// 推送批次。
class SyncPushBatch {
  const SyncPushBatch({required this.patches});
  final List<EntryPatch> patches;

  Map<String, dynamic> toJson() =>
      {'patches': patches.map((p) => p.toJson()).toList()};

  static SyncPushBatch fromJson(Map<String, dynamic> j) => SyncPushBatch(
        patches: (j['patches'] as List)
            .map((p) => EntryPatch.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

Map<String, dynamic> _fieldToJson(FieldValue f) => {'v': f.v, 't': f.t};
FieldValue _fieldFromJson(Map<String, dynamic> j) =>
    FieldValue(j['v'], j['t'] as int);
Map<String, dynamic> _entryToJson(SyncEntry e) => {
  'id': e.id,
  'createdAt': e.createdAt,
  'fields': e.fields.map((k, v) => MapEntry(k, _fieldToJson(v))),
};
SyncEntry _entryFromJson(Map<String, dynamic> j) => SyncEntry(
      id: j['id'] as String,
      createdAt: j['createdAt'] as int,
      fields: (j['fields'] as Map).map(
          (k, v) => MapEntry(k as String, _fieldFromJson(v as Map<String, dynamic>))),
    );

/// JSON 编解码入口，供 RemoteRepo 与服务端 handler 共用，宿主测试验证往返。
class SyncCodec {
  const SyncCodec();

  String encodePull(SyncPullResponse r) => jsonEncode(r.toJson());
  SyncPullResponse decodePull(String s) =>
      SyncPullResponse.fromJson(jsonDecode(s) as Map<String, dynamic>);

  String encodePush(SyncPushBatch b) => jsonEncode(b.toJson());
  SyncPushBatch decodePush(String s) =>
      SyncPushBatch.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
