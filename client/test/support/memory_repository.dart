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

  Completer<void>? gate;

  @override
  Future<void> save(Entry entry) async {
    saves++;
    final waitFor = gate;
    if (waitFor != null) await waitFor.future;
    if (failSave) throw StateError('simulated disk failure');
    entries[entry.id] = entry;
  }

  @override
  Future<List<Entry>> list({EntryCursor? before, int limit = 30}) async {
    if (failList) throw StateError('simulated read failure');
    final sorted = entries.values.toList()
      ..sort((a, b) {
        final time = b.createdAt.compareTo(a.createdAt);
        return time == 0 ? b.id.compareTo(a.id) : time;
      });
    return sorted
        .where(
          (e) =>
              e.deletedAt == null &&
              (before == null ||
                  e.createdAt.isBefore(before.createdAt) ||
                  (e.createdAt == before.createdAt &&
                      e.id.compareTo(before.id) < 0)),
        )
        .take(limit)
        .toList();
  }

  @override
  Future<List<Entry>> exportAll() async {
    final sorted = entries.values.toList()
      ..sort((a, b) {
        final time = b.createdAt.compareTo(a.createdAt);
        return time == 0 ? b.id.compareTo(a.id) : time;
      });
    return sorted;
  }

  @override
  Future<List<Entry>> listDeleted({int limit = 30}) async {
    final sorted = entries.values.where((e) => e.deletedAt != null).toList()
      ..sort((a, b) {
        final time = b.deletedAt!.compareTo(a.deletedAt!);
        return time == 0 ? b.id.compareTo(a.id) : time;
      });
    return sorted.take(limit).toList();
  }

  @override
  Future<void> softDelete(String id) async {
    if (failDelete) throw StateError('simulated delete failure');
    final existing = entries[id];
    if (existing == null) throw StateError('no such entry: $id');
    final stamp = _now().toUtc();
    entries[id] = Entry(
      id: existing.id,
      content: existing.content,
      createdAt: existing.createdAt,
      updatedAt: stamp,
      dayKey: existing.dayKey,
      deletedAt: stamp,
    );
  }

  @override
  Future<void> restore(String id) async {
    final existing = entries[id];
    if (existing == null) throw StateError('no such entry: $id');
    if (existing.deletedAt == null) {
      throw StateError('entry is not deleted: $id');
    }
    final stamp = _now().toUtc();
    entries[id] = Entry(
      id: existing.id,
      content: existing.content,
      createdAt: existing.createdAt,
      updatedAt: stamp,
      dayKey: existing.dayKey,
    );
  }

  @override
  Future<void> purge(String id) async {
    if (failDelete) throw StateError('simulated delete failure');
    if (!entries.containsKey(id)) throw StateError('no such entry: $id');
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
