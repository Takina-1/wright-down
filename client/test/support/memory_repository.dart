import 'dart:async';

import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/import_summary.dart';
import 'package:local_diary/src/domain/local_entry_repository.dart';

import 'entry_merger.dart';

class MemoryRepository implements LocalEntryRepository {
  /// 可注入时钟：软删除与恢复用它打时间戳，保证用例断言的时间是确定的。
  /// 写进 [Entry.deletedAt] 的时间统一转成 UTC。
  MemoryRepository({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  final Map<String, Entry> entries = {};
  int saves = 0;
  bool failSave = false;
  bool failList = false;
  bool failImport = false;

  /// 删除类操作（软删除、彻底删除、清空回收站）统一失败开关。
  bool failDelete = false;

  /// 回收站读取失败开关。只影响 [listDeleted]，与 [failList] 相互独立。
  bool failListDeleted = false;

  /// 保存挂起点：置为未完成的 Completer 时，[save] 会先挂起。
  Completer<void>? gate;

  /// 软删除挂起点：置为未完成的 Completer 时，[softDelete] 会先挂起。
  ///
  /// 与 [gate] 相互独立：一个挂起保存，一个挂起删除，方便分别构造
  /// 「正在保存」和「正在删除」两种中间态。
  Completer<void>? deleteGate;

  @override
  Future<void> save(Entry entry) async {
    saves++;
    final waitFor = gate;
    if (waitFor != null) await waitFor.future;
    if (failSave) throw StateError('simulated disk failure');
    final existing = entries[entry.id];
    if (existing == null) {
      entries[entry.id] = entry;
      return;
    }
    // 与生产实现口径一致：更新分支只写正文与修改时间，创建时间、日期键、
    // 删除标记都沿用库里已有的值。
    // 调用方（编辑器）构造的 Entry 不带 deletedAt，若整体替换，
    // 已软删除的条目会被复活回到时间轴。
    entries[entry.id] = Entry(
      id: existing.id,
      content: entry.content,
      createdAt: existing.createdAt,
      updatedAt: entry.updatedAt,
      dayKey: existing.dayKey,
      deletedAt: entry.deletedAt ?? existing.deletedAt,
    );
  }

  @override
  Future<List<Entry>> list({EntryCursor? before, int limit = 30}) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    if (failList) throw StateError('simulated read failure');
    return _sortedByCreated()
        .where((e) {
          if (e.deletedAt != null) return false;
          if (before == null) return true;
          // 与生产实现口径一致：游标比较用毫秒 epoch，不用微秒精度的 DateTime。
          final created = e.createdAt.millisecondsSinceEpoch;
          final cursor = before.createdAt.millisecondsSinceEpoch;
          return created < cursor ||
              (created == cursor && e.id.compareTo(before.id) < 0);
        })
        .take(limit)
        .toList();
  }

  @override
  Future<List<Entry>> exportAll() async {
    return _sortedByCreated();
  }

  /// 按创建时间倒序（毫秒精度），同毫秒按 id 倒序——与生产实现的排序口径一致。
  List<Entry> _sortedByCreated() {
    final sorted = entries.values.toList()
      ..sort((a, b) {
        final time = b.createdAt.millisecondsSinceEpoch.compareTo(
          a.createdAt.millisecondsSinceEpoch,
        );
        return time == 0 ? b.id.compareTo(a.id) : time;
      });
    return sorted;
  }

  @override
  Future<List<Entry>> listDeleted({int limit = 30}) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    if (failListDeleted) throw StateError('simulated read failure');
    final sorted = entries.values.where((e) => e.deletedAt != null).toList()
      ..sort((a, b) {
        // 与生产实现口径一致：按 epoch 毫秒整数比较，不用微秒精度的 DateTime。
        final time = b.deletedAt!.millisecondsSinceEpoch
            .compareTo(a.deletedAt!.millisecondsSinceEpoch);
        return time == 0 ? b.id.compareTo(a.id) : time;
      });
    return sorted.take(limit).toList();
  }

  @override
  Future<void> softDelete(String id) async {
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
    final waitFor = deleteGate;
    if (waitFor != null) await waitFor.future;
    if (failDelete) throw StateError('simulated delete failure');
    final existing = entries[id];
    if (existing == null) throw StateError('No such entry: $id');
    final now = _now().toUtc();
    // 版本戳只许增不许减：与生产实现一致，设备时钟回拨时不写小。
    final stamp = _monotonicStamp(existing.updatedAt, now);
    entries[id] = Entry(
      id: existing.id,
      content: existing.content,
      createdAt: existing.createdAt,
      updatedAt: stamp,
      dayKey: existing.dayKey,
      // 删除时间记的是删除发生的墙上时间，与版本戳分开。
      deletedAt: now,
    );
  }

  @override
  Future<void> restore(String id) async {
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
    final existing = entries[id];
    // 与生产实现一致：不存在与未删除共用同一条错误消息。
    if (existing == null || existing.deletedAt == null) {
      throw StateError('Entry $id is not in the trash');
    }
    final now = _now().toUtc();
    final stamp = _monotonicStamp(existing.updatedAt, now);
    entries[id] = Entry(
      id: existing.id,
      content: existing.content,
      createdAt: existing.createdAt,
      updatedAt: stamp,
      dayKey: existing.dayKey,
    );
  }

  /// 取当前版本戳与当前时刻的较大者，保证版本戳只增不减。
  DateTime _monotonicStamp(DateTime current, DateTime now) {
    if (current.millisecondsSinceEpoch > now.millisecondsSinceEpoch) {
      return DateTime.fromMillisecondsSinceEpoch(
        current.millisecondsSinceEpoch,
        isUtc: true,
      );
    }
    return now;
  }

  @override
  Future<void> purge(String id) async {
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
    if (failDelete) throw StateError('simulated delete failure');
    final existing = entries[id];
    // 只允许彻底删除回收站里的条目：活着条目误传 id 也不会被物理移除。
    if (existing == null) throw StateError('No such entry: $id');
    if (existing.deletedAt == null) {
      throw StateError('Entry $id is not in the trash');
    }
    entries.remove(id);
  }

  @override
  Future<int> purgeAll() async {
    if (failDelete) throw StateError('simulated delete failure');
    final deleted = entries.values.where((e) => e.deletedAt != null).toList();
    for (final entry in deleted) {
      entries.remove(entry.id);
    }
    return deleted.length;
  }

  @override
  Future<ImportSummary> importAll(List<Entry> incoming) async {
    if (failImport) throw StateError('simulated import failure');
    return mergeEntries(entries, incoming);
  }

  @override
  Future<void> close() async {}
}
