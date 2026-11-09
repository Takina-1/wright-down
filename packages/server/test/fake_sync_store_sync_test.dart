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

    test('跨用户同 id 不互相覆盖：A 的条目不会被 B 的同名条目顶掉', () async {
      // 条目主键是 (user_id, id)。若按单列 id 索引，B 推送 e1 会覆盖 A 的 e1，
      // 导致 A 的日记丢失、B 读到别人的内容（与 deploy/sql/schema.sql 的主键不一致）。
      final store = FakeSyncStore();
      final a = await store.register('a@b.com', 'pw');
      final b = await store.register('b@b.com', 'pw');

      await store.push(a.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 100, fields: const {
          'content': FieldValue('A 的日记', 100),
        }),
      ]));
      await store.push(b.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 200, fields: const {
          'content': FieldValue('B 的日记', 200),
        }),
      ]));

      final pulledA = await store.pull(a.userId, 0);
      expect(pulledA.entries, hasLength(1));
      expect(pulledA.entries.single.fields['content'],
          const FieldValue('A 的日记', 100));

      final pulledB = await store.pull(b.userId, 0);
      expect(pulledB.entries, hasLength(1));
      expect(pulledB.entries.single.fields['content'],
          const FieldValue('B 的日记', 200));
    });

    test('跨用户同 id 各自独立合并：A 的后续更新不会污染 B', () async {
      final store = FakeSyncStore();
      final a = await store.register('a@b.com', 'pw');
      final b = await store.register('b@b.com', 'pw');

      await store.push(a.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 100, fields: const {
          'content': FieldValue('A1', 100),
          'mood': FieldValue('calm', 100),
        }),
      ]));
      await store.push(b.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 100, fields: const {
          'content': FieldValue('B1', 100),
        }),
      ]));
      // A 再推一次：只应改 A 自己的 e1
      await store.push(a.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 100, fields: const {
          'content': FieldValue('A2', 200),
        }),
      ]));

      final pulledA = await store.pull(a.userId, 0);
      expect(pulledA.entries.single.fields['content'],
          const FieldValue('A2', 200));
      expect(pulledA.entries.single.fields['mood'], const FieldValue('calm', 100));

      final pulledB = await store.pull(b.userId, 0);
      expect(pulledB.entries.single.fields['content'],
          const FieldValue('B1', 100));
      expect(pulledB.entries.single.fields.containsKey('mood'), isFalse);
    });

    test('用户 id 分配不占用条目 seq：首个 push 的 seq 从 1 开始', () async {
      // register 曾复用条目 seq 计数器，导致首条日记 seq=2、游标推进到 2，
      // 与计划里 DP-02 期望的 cursor:1 不一致。
      final store = FakeSyncStore();
      final r = await store.register('a@b.com', 'pw');
      await store.push(r.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 1, fields: const {
          'content': FieldValue('a', 100),
        }),
      ]));
      final pulled = await store.pull(r.userId, 0);
      expect(pulled.cursor, 1);
    });
  });
}
