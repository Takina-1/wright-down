import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
    required this.cos,
    required this.now,
  }) : _stateController = StreamController<SyncState>.broadcast();

  final LocalEntryRepository repository;
  final SyncRemote remote;
  final AuthProvider auth;
  final CosGateway cos;

  // 预留给未来时间戳需求（如记录 lastSyncedAt）；当前触发循环与退避
  // 不读当前时间，故字段仍未被读取。
  // ignore: unused_field
  final NowFn now;

  int _cursor = 0;

  /// 状态广播流。stop() 关闭后由 start() 重建（非 final：stop→start 循环
  /// 需要重新创建控制器，避免复用死流）。
  StreamController<SyncState> _stateController;
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
    var entries = await repository.exportAll();
    // 照片上传：photo 有 BLOB 但 photoKey 缺失或与内容不匹配（同条目换过照片）
    // 的条目，上传 COS 并设 key。photoKey 恒为照片内容 sha256——hash 不匹配
    // 即照片已变（T-12 修复）。
    // 用 saveMerged 保留既有 sync_stamps（含 photo 戳），避免 save 重算时间戳。
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.photo != null &&
          (e.photoKey == null || _photoHash(e.photo!) != e.photoKey!)) {
        final key = await cos.upload(e.photo!);
        final stamps = {...e.syncStamps, 'photo': now().millisecondsSinceEpoch};
        final updated = Entry(
          id: e.id,
          content: e.content,
          createdAt: e.createdAt,
          updatedAt: e.updatedAt,
          dayKey: e.dayKey,
          deletedAt: e.deletedAt,
          mood: e.mood,
          tags: e.tags,
          photo: e.photo,
          photoKey: key,
          syncStamps: stamps,
        );
        await repository.saveMerged(updated);
        entries[i] = updated;
      }
    }
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
      final merged = existing == null
          ? _fromSyncEntry(remoteEntry)
          : applyRemote(existing, remoteEntry);
      await repository.saveMerged(merged);
      // 照片下载：photoKey 有但本地 photo BLOB 缺失，或本地 BLOB 与远端 key
      // 不匹配（远端照片已变更，本地缓存失效）——下载覆盖（T-12 修复）。
      // 用 saveMerged 保留 photoKey 与 photo 戳（photo 是本地缓存不进 sync 字段）。
      if (merged.photoKey != null &&
          (merged.photo == null ||
              _photoHash(merged.photo!) != merged.photoKey!)) {
        final bytes = await cos.download(merged.photoKey!);
        final withPhoto = Entry(
          id: merged.id,
          content: merged.content,
          createdAt: merged.createdAt,
          updatedAt: merged.updatedAt,
          dayKey: merged.dayKey,
          deletedAt: merged.deletedAt,
          mood: merged.mood,
          tags: merged.tags,
          photo: bytes,
          photoKey: merged.photoKey,
          syncStamps: merged.syncStamps,
        );
        await repository.saveMerged(withPhoto);
      }
    }
  }

  /// 启动同步：若已在运行则忽略；否则开启 5 分钟周期拉取并立即触发一次 pull。
  void start() {
    if (_pullTimer != null) return;
    // stop() 会关闭状态流——start 重建（复用死流会导致后续状态广播被静默丢弃）。
    if (_stateController.isClosed) {
      _stateController = StreamController<SyncState>.broadcast();
      _stateValue = SyncState.idle;
    }
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

  /// 触发推送：登录态预检通过后，取消既有防抖并安排 [debounce] 后推送
  /// （合并多次写入为一次往返）。未登录时直接跳过——登出后不浪费一次推送循环。
  void triggerPush({Duration debounce = const Duration(seconds: 30)}) {
    unawaited(_me().then((me) {
      if (me == null) return; // T-11：未登录不安排推送。
      _schedulePush(debounce: debounce);
    }));
  }

  /// 安排推送防抖（登录态已确认）。
  void _schedulePush({Duration debounce = const Duration(seconds: 30)}) {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(debounce, () async {
      try {
        await _pushWithRetry();
        _setState(SyncState.synced);
      } catch (_) {
        // T-09：推送失败不静默——置 failed，UI 监听 failed 提示
        // （与 triggerPull 的状态语义对称）。
        _setState(SyncState.failed);
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
      photoKey: fields['photo']?.v as String?,
      syncStamps: fields.map((k, v) => MapEntry(k, v.t)),
    );
  }

  /// 照片内容 sha256 hex——与 FakeCos/HttpCosGateway 的 photoKey 口径一致。
  static String _photoHash(Uint8List bytes) =>
      sha256.convert(bytes).toString();

  /// dayKey 必须是零填充的 ISO 日期，形如 2026-11-03。
  String _dayKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
