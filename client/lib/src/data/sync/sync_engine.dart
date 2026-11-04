import 'dart:async';
import 'dart:io';

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

/// 同步状态：idle 未启动 / syncing 同步中 / synced 已同步 / failed 失败。
enum SyncState { idle, syncing, synced, failed }

/// 同步引擎：LocalRepo 的异步旁路。推读脏→RemoteRepo.push；
/// 拉 RemoteRepo.pull→applyRemote 写 LocalRepo。
///
/// 本 Part 提供同步 [pushOnce]/[pullOnce] 供测试；触发循环（启动/前台/定时）
/// 与退避重试在 Part 3b 接入 UI 生命周期。
class SyncEngine {
  /// 退避纯函数：attempt 从 0 起，2→4→8→16→32 秒封顶。
  static int nextBackoff(int attempt) => (1 << (attempt + 1)).clamp(2, 32);

  SyncEngine({
    required this.repository,
    required this.remote,
    required this.auth,
    required this.now,
  });

  final LocalEntryRepository repository;
  final SyncRemote remote;
  final AuthProvider auth;

  // 预留给未来时间戳需求（如记录 lastSyncedAt）；当前触发循环与退避
  // 不读当前时间，故字段仍未被读取。
  // ignore: unused_field
  final NowFn now;

  int _cursor = 0;

  final StreamController<SyncState> _stateController =
      StreamController<SyncState>.broadcast();
  SyncState _stateValue = SyncState.idle;
  Timer? _pullTimer;
  Timer? _pushDebounce;

  Stream<SyncState> get stateChanged => _stateController.stream;
  SyncState get state => _stateValue;

  void _setState(SyncState s) {
    _stateValue = s;
    // stop 可能已关闭控制器（且停止前有在途 pull），关闭后再 add 会抛错，
    // 故先判 isClosed：状态值仍更新，但不再向已关闭的流广播。
    if (!_stateController.isClosed) _stateController.add(s);
  }

  Future<AuthResult?> _me() async {
    final r = await auth.current();
    return r;
  }

  /// 推一次：读全部条目（含软删除条目，其 deletedAt 字段携带删除标记
  /// 与 stamp），构批次推给服务端。成功后不清除 syncStamps
  /// （时间戳即「已同步」标记：服务端已含该戳的字段不会再被更旧的推覆盖）。
  Future<void> pushOnce() async {
    final me = await _me();
    if (me == null) return;
    final entries = await repository.exportAll();
    final patches = entries
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
        await repository.saveMerged(_fromSyncEntry(remoteEntry));
      } else {
        await repository.saveMerged(applyRemote(existing, remoteEntry));
      }
    }
  }

  /// 启动同步：若已在运行则忽略；否则开启 5 分钟周期拉取并立即触发一次 pull。
  void start() {
    if (_pullTimer != null) return;
    _pullTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(triggerPull()),
    );
    unawaited(triggerPull()); // 启动即拉一次
  }

  /// 停止同步：取消拉取/推送定时器并关闭状态流。
  void stop() {
    _pullTimer?.cancel();
    _pullTimer = null;
    _pushDebounce?.cancel();
    _pushDebounce = null;
    _stateController.close();
  }

  /// 触发一次拉取：已在同步中则忽略；成功置 [SyncState.synced]，失败置
  /// [SyncState.failed]（401/格式错误/退避耗尽均归为失败，UI 监听 failed 提示）。
  Future<void> triggerPull() async {
    if (state == SyncState.syncing) return;
    _setState(SyncState.syncing);
    try {
      await _pullWithRetry();
      _setState(SyncState.synced);
    } catch (_) {
      _setState(SyncState.failed);
    }
  }

  /// 触发推送：取消既有防抖后，安排 30 秒后推送（合并多次写入为一次往返）。
  void triggerPush() {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(seconds: 30), () async {
      try {
        await _pushWithRetry();
      } catch (_) {
        // 推送失败不阻塞 UI：下次写触发或下次 pull 时重试。
      }
    });
  }

  /// 退避重试拉取：遇 [SocketException]（网络）按 2→4→8→16→32 秒退避重试，
  /// 最多 6 次后放弃本轮；其余异常（401、格式错误等）不重试，直接向上抛。
  Future<void> _pullWithRetry() async {
    var attempt = 0;
    while (true) {
      try {
        await pullOnce();
        return;
      } on SocketException {
        if (attempt >= 5) {
          throw StateError('pull retry exhausted after $attempt attempts');
        }
        await Future.delayed(Duration(seconds: nextBackoff(attempt)));
        attempt++;
      }
    }
  }

  /// 退避重试推送：结构与 [_pullWithRetry] 一致。
  Future<void> _pushWithRetry() async {
    var attempt = 0;
    while (true) {
      try {
        await pushOnce();
        return;
      } on SocketException {
        if (attempt >= 5) {
          throw StateError('push retry exhausted after $attempt attempts');
        }
        await Future.delayed(Duration(seconds: nextBackoff(attempt)));
        attempt++;
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
