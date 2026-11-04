import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/sync/entry_sync_map.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  test('toSyncEntry 含 photoKey 时输出 photo 字段', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);
    final e = Entry(id: 'e1', content: 'x', createdAt: now, updatedAt: now,
      dayKey: '2026-11-03', photoKey: 'key-1', syncStamps: const {'photo': 5000});
    final s = toSyncEntry(e);
    expect(s.fields['photo'], const FieldValue('key-1', 5000));
  });

  test('toSyncEntry 无 photoKey 且无戳时不输出 photo 字段', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);
    final e = Entry(id: 'e1', content: 'x', createdAt: now, updatedAt: now,
      dayKey: '2026-11-03', photoKey: null, syncStamps: const {});
    final s = toSyncEntry(e);
    expect(s.fields.containsKey('photo'), isFalse);
  });

  test('toSyncEntry photoKey 为 null 但有戳时输出 FieldValue(null, stamp) 删除语义', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);
    final e = Entry(id: 'e1', content: 'x', createdAt: now, updatedAt: now,
      dayKey: '2026-11-03', photoKey: null, syncStamps: const {'photo': 5000});
    final s = toSyncEntry(e);
    expect(s.fields['photo'], const FieldValue(null, 5000));
  });

  test('applyRemote 用远端 photo 覆盖本地 photoKey', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);
    final local = Entry(id: 'e1', content: 'x', createdAt: now, updatedAt: now,
      dayKey: '2026-11-03', photoKey: 'old', syncStamps: const {'photo': 100});
    final remote = SyncEntry(id: 'e1', createdAt: 1000, fields: const {'photo': FieldValue('new-key', 500)});
    final merged = applyRemote(local, remote);
    expect(merged.photoKey, 'new-key');
    expect(merged.syncStamps['photo'], 500);
  });

  test('applyRemote 远端 photo 较旧时保留本地 photoKey', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);
    final local = Entry(id: 'e1', content: 'x', createdAt: now, updatedAt: now,
      dayKey: '2026-11-03', photoKey: 'local-key', syncStamps: const {'photo': 800});
    final remote = SyncEntry(id: 'e1', createdAt: 1000, fields: const {'photo': FieldValue('stale', 200)});
    final merged = applyRemote(local, remote);
    expect(merged.photoKey, 'local-key');
    expect(merged.syncStamps['photo'], 800);
  });

  test('applyRemote 远端 photo 为 null 且较新时清空本地 photoKey', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);
    final local = Entry(id: 'e1', content: 'x', createdAt: now, updatedAt: now,
      dayKey: '2026-11-03', photoKey: 'old', syncStamps: const {'photo': 100});
    final remote = SyncEntry(id: 'e1', createdAt: 1000, fields: const {'photo': FieldValue(null, 900)});
    final merged = applyRemote(local, remote);
    expect(merged.photoKey, isNull);
    expect(merged.syncStamps['photo'], 900);
  });
}
