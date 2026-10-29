import 'dart:async';

import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/import_summary.dart';
import 'package:local_diary/src/domain/local_entry_repository.dart';

class MemoryRepository implements LocalEntryRepository {
  final Map<String, Entry> entries = {};
  int saves = 0;
  bool failSave = false;
  bool failList = false;
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
              before == null ||
              e.createdAt.isBefore(before.createdAt) ||
              (e.createdAt == before.createdAt &&
                  e.id.compareTo(before.id) < 0),
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
  Future<ImportSummary> importAll(List<Entry> incoming) async {
    var inserted = 0;
    var updated = 0;
    var skipped = 0;
    for (final entry in incoming) {
      final existing = entries[entry.id];
      if (existing == null) {
        entries[entry.id] = entry;
        inserted++;
      } else if (entry.updatedAt.millisecondsSinceEpoch >
          existing.updatedAt.millisecondsSinceEpoch) {
        entries[entry.id] = Entry(
          id: existing.id,
          content: entry.content,
          createdAt: existing.createdAt,
          updatedAt: entry.updatedAt,
          dayKey: existing.dayKey,
        );
        updated++;
      } else {
        skipped++;
      }
    }
    return ImportSummary(
      inserted: inserted,
      updated: updated,
      skipped: skipped,
    );
  }

  @override
  Future<void> close() async {}
}
