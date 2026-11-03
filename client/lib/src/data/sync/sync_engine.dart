import 'dart:async';

import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/local_entry_repository.dart';
import 'package:local_diary/src/domain/sync/entry_sync_map.dart';
import 'package:sync_core/sync_core.dart';

/// SyncEngine 依赖的最小远程接口：只暴露推拉两个往返，便于测试注入替身。
/// [RemoteRepo] 实现本接口；测试的 `_FakeRemote` 同样实现本接口，避开
/// RemoteRepo 的 http client/baseUrl/codec/handler/register/login 全接口。
abstract interface class SyncRemote {
  Future<SyncPullResponse> pull(String token, int cursor);
  Future<void> push(String token, SyncPushBatch batch);
}

/// 当前时间取值函数，便于测试注入固定时钟。
typedef NowFn = DateTime Function();

/// 同步引擎：LocalRepo 的异步旁路。推读脏→RemoteRepo.push；
/// 拉 RemoteRepo.pull→applyRemote 写 LocalRepo。
///
/// 本 Part 提供同步 [pushOnce]/[pullOnce] 供测试；触发循环（启动/前台/定时）
/// 与退避重试在 Part 3b 接入 UI 生命周期。
class SyncEngine {
  SyncEngine({
    required this.repository,
    required this.remote,
    required this.auth,
    required this.now,
  });

  final LocalEntryRepository repository;
  final SyncRemote remote;
  final AuthProvider auth;

  // 预留给 Part 3b 的退避重试与触发循环读取当前时间；本 Part 的最小
  // pushOnce/pullOnce 不读当前时间，故字段当前未被读取。
  // ignore: unused_field
  final NowFn now;

  int _cursor = 0;

  Future<AuthResult?> _me() async {
    final r = await auth.current();
    return r;
  }

  /// 推一次：读全部未删条目，构批次推给服务端。成功后不清除 syncStamps
  /// （时间戳即「已同步」标记：服务端已含该戳的字段不会再被更旧的推覆盖）。
  Future<void> pushOnce() async {
    final me = await _me();
    if (me == null) return;
    final entries = await repository.exportAll();
    final patches = entries
        .where((e) => !e.isDeleted)
        .map((e) => EntryPatch(
            id: e.id,
            createdAt: e.createdAt.millisecondsSinceEpoch,
            fields: toSyncEntry(e).fields))
        .toList();
    if (patches.isEmpty) return;
    await remote.push(me.token, SyncPushBatch(patches: patches));
  }

  /// 拉一次：拉远端变更，字段级 LWW 合并入本地，推进 cursor。
  Future<void> pullOnce() async {
    final me = await _me();
    if (me == null) return;
    final result = await remote.pull(me.token, _cursor);
    _cursor = result.cursor;
    for (final remoteEntry in result.entries) {
      // 在本地全部条目里找同 id：找到则字段级 LWW 合并，找不到则新建。
      Entry? existing;
      for (final e in await repository.exportAll()) {
        if (e.id == remoteEntry.id) {
          existing = e;
          break;
        }
      }
      if (existing == null) {
        await repository.save(_fromSyncEntry(remoteEntry));
      } else {
        await repository.save(applyRemote(existing, remoteEntry));
      }
    }
  }

  /// 把远端 SyncEntry 还原成本地 Entry（新建用）。字段级时间戳取远端字段的 t，
  /// createdAt/dayKey 由远端 createdAt 推导；updatedAt 暂用 createdAt
  /// （远端 createdAt 即条目创建时刻，pull 最小实现里尚未区分创建与最近更新）。
  Entry _fromSyncEntry(SyncEntry s) {
    final fields = s.fields;
    final createdAt =
        DateTime.fromMillisecondsSinceEpoch(s.createdAt, isUtc: true);
    return Entry(
      id: s.id,
      content: (fields['content']?.v as String?) ?? '',
      createdAt: createdAt,
      updatedAt: createdAt,
      dayKey: _dayKey(createdAt),
      deletedAt: fields['deletedAt']?.v == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              fields['deletedAt']!.v as int, isUtc: true),
      mood: fields['mood']?.v as String?,
      tags: (fields['tags']?.v as List?)?.cast<String>() ?? const [],
      syncStamps: fields.map((k, v) => MapEntry(k, v.t)),
    );
  }

  /// dayKey 必须是零填充的 ISO 日期，形如 2026-11-03。
  String _dayKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
