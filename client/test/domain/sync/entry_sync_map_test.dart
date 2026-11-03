import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/sync/entry_sync_map.dart';
import 'package:sync_core/sync_core.dart';

Entry _e(String id, {String content = 'c', String? mood, List<String> tags = const [], int? deletedAt, Map<String, int> stamps = const {}}) {
  final now = 1000;
  return Entry(
    id: id, content: content,
    createdAt: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
    dayKey: '2026-11-03', deletedAt: deletedAt != null ? DateTime.fromMillisecondsSinceEpoch(deletedAt, isUtc: true) : null,
    mood: mood, tags: tags, syncStamps: stamps,
  );
}

void main() {
  group('toSyncEntry', () {
    test('Entry 映射为带时间戳的 SyncEntry', () {
      final e = _e('e1', content: 'hello', mood: 'happy', tags: ['a'], stamps: const {'content': 200, 'mood': 200, 'tags': 200});
      final s = toSyncEntry(e);
      expect(s.id, 'e1');
      expect(s.fields['content'], const FieldValue('hello', 200));
      expect(s.fields['mood'], const FieldValue('happy', 200));
      expect(s.fields['tags'], const FieldValue(['a'], 200));
    });
  });

  group('applyRemote', () {
    test('远端字段较新则覆盖，较旧则保留', () {
      final local = _e('e1', content: 'local', stamps: const {'content': 300, 'mood': 100});
      final remote = SyncEntry(id: 'e1', createdAt: 1000, fields: const {
        'content': FieldValue('remote-old', 200),
        'mood': FieldValue('excited', 200),
      });
      final merged = applyRemote(local, remote);
      expect(merged.content, 'local');       // 本地新，保留
      expect(merged.mood, 'excited');        // 远端新，覆盖
      expect(merged.syncStamps['content'], 300); // 本地戳不变
      expect(merged.syncStamps['mood'], 200);    // 远端戳更新
    });

    test('远端较新的字段覆盖并更新本地戳', () {
      final local = _e('e1', content: 'old', stamps: const {'content': 100});
      final remote = SyncEntry(id: 'e1', createdAt: 1000, fields: const {
        'content': FieldValue('new', 500),
      });
      final merged = applyRemote(local, remote);
      expect(merged.content, 'new');
      expect(merged.syncStamps['content'], 500);
    });

    test('远端未提供 mood 时保留本地心情', () {
      final local = _e('e1', content: 'c', mood: 'happy', stamps: const {'mood': 100});
      final remote = SyncEntry(id: 'e1', createdAt: 1000, fields: const {
        'content': FieldValue('new', 500),
      });
      final merged = applyRemote(local, remote);
      expect(merged.mood, 'happy'); // 远端无 mood，保留本地
    });

    test('远端 mood 较旧时保留本地心情', () {
      final local = _e('e1', content: 'c', mood: 'happy', stamps: const {'mood': 300});
      final remote = SyncEntry(id: 'e1', createdAt: 1000, fields: const {
        'mood': FieldValue('excited', 200),
      });
      final merged = applyRemote(local, remote);
      expect(merged.mood, 'happy'); // 远端旧，保留本地
    });
  });
}
