import 'package:test/test.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  group('SyncCodec', () {
    test('拉取响应往返一致', () {
      const codec = SyncCodec();
      final original = SyncPullResponse(
        cursor: 42,
        entries: [
          SyncEntry(
            id: 'e1',
            createdAt: 1000,
            fields: const {
              'content': FieldValue('hello', 2000),
              'mood': FieldValue('happy', 2000),
              'tags': FieldValue(const ['a', 'b'], 2000),
            },
          ),
        ],
      );
      final restored = codec.decodePull(codec.encodePull(original));
      expect(restored.cursor, 42);
      expect(restored.entries.single.id, 'e1');
      expect(restored.entries.single.fields['content'],
          const FieldValue('hello', 2000));
      expect(restored.entries.single.fields['tags']?.v, const ['a', 'b']);
    });

    test('推送批次往返一致', () {
      const codec = SyncCodec();
      final batch = SyncPushBatch(patches: [
        EntryPatch(
          id: 'e1',
          createdAt: 1000,
          fields: const {
            'content': FieldValue('new', 3000),
            'deletedAt': FieldValue(null, 3000),
          },
        ),
      ]);
      final restored = codec.decodePush(codec.encodePush(batch));
      expect(restored.patches.single.id, 'e1');
      expect(restored.patches.single.fields['content'],
          const FieldValue('new', 3000));
      expect(restored.patches.single.fields['deletedAt']?.v, isNull);
    });

    test('空字段映射不崩', () {
      const codec = SyncCodec();
      final batch = SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 1, fields: const {}),
      ]);
      final restored = codec.decodePush(codec.encodePush(batch));
      expect(restored.patches.single.fields, isEmpty);
    });
  });
}
