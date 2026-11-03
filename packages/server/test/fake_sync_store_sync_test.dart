import 'package:test/test.dart';
import 'package:server/server.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  group('FakeSyncStore 同步', () {
    test('push 后能 pull 到', () async {
      final store = FakeSyncStore();
      final r = await store.register('a@b.com', 'pw');
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(
          id: 'e1',
          createdAt: 1000,
          fields: const {'content': FieldValue('hello', 2000)},
        ),
      ]));
      final pulled = await store.pull(r.userId, 0);
      expect(pulled.entries.single.id, 'e1');
      expect(pulled.entries.single.fields['content'],
          const FieldValue('hello', 2000));
      expect(pulled.cursor > 0, isTrue);
    });

    test('字段级冲突：后推送的较新字段覆盖，较旧的不覆盖', () async {
      final store = FakeSyncStore();
      final r = await store.register('a@b.com', 'pw');
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 1, fields: const {
          'content': FieldValue('from-A', 200),
          'mood': FieldValue('calm', 200),
        }),
      ]));
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 1, fields: const {
          'content': FieldValue('from-B-old', 100),
          'mood': FieldValue('excited', 300),
        }),
      ]));
      final pulled = await store.pull(r.userId, 0);
      final fields = pulled.entries.single.fields;
      expect(fields['content'], const FieldValue('from-A', 200));
      expect(fields['mood'], const FieldValue('excited', 300));
    });

    test('游标推进：只返回 seq > cursor 的条目', () async {
      final store = FakeSyncStore();
      final r = await store.register('a@b.com', 'pw');
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 1, fields: const {
          'content': FieldValue('a', 100),
        }),
      ]));
      final first = await store.pull(r.userId, 0);
      expect(first.entries, hasLength(1));
      final c = first.cursor;
      final again = await store.pull(r.userId, c);
      expect(again.entries, isEmpty);
      expect(again.cursor, c);
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e2', createdAt: 2, fields: const {
          'content': FieldValue('b', 100),
        }),
      ]));
      final next = await store.pull(r.userId, c);
      expect(next.entries.single.id, 'e2');
    });

    test('createdAt 不可变：更新条目保留原 createdAt', () async {
      final store = FakeSyncStore();
      final r = await store.register('a@b.com', 'pw');
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 999, fields: const {
          'content': FieldValue('v1', 100),
        }),
      ]));
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 1, fields: const {
          'content': FieldValue('v2', 200),
        }),
      ]));
      final pulled = await store.pull(r.userId, 0);
      expect(pulled.entries.single.createdAt, 999);
      expect(pulled.entries.single.fields['content'], const FieldValue('v2', 200));
    });
  });
}
