import 'package:test/test.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  group('mergeFieldLww', () {
    test('incoming 版本戳更大则赢', () {
      final a = const FieldValue('old', 100);
      final b = const FieldValue('new', 200);
      expect(mergeFieldLww(a, b), const FieldValue('new', 200));
    });

    test('incoming 版本戳更小则输', () {
      final a = const FieldValue('new', 200);
      final b = const FieldValue('old', 100);
      expect(mergeFieldLww(a, b), const FieldValue('new', 200));
    });

    test('版本戳相等取 incoming（推送方）', () {
      final a = const FieldValue('local', 200);
      final b = const FieldValue('pushed', 200);
      expect(mergeFieldLww(a, b), const FieldValue('pushed', 200));
    });
  });

  group('mergeSyncEntry', () {
    test('逐字段合并：本地没有的字段直接采用 incoming', () {
      final local = const {'content': FieldValue('a', 100)};
      final incoming = SyncEntry(
        id: 'e1',
        createdAt: 1,
        fields: const {
          'content': FieldValue('b', 200),
          'mood': FieldValue('happy', 200),
        },
      );
      final merged = mergeSyncEntry(local, incoming);
      expect(merged['content'], const FieldValue('b', 200));
      expect(merged['mood'], const FieldValue('happy', 200));
    });

    test('逐字段合并：本地字段更新时不被较旧的 incoming 覆盖', () {
      final local = const {
        'content': FieldValue('local-new', 300),
        'mood': FieldValue('calm', 100),
      };
      final incoming = SyncEntry(
        id: 'e1',
        createdAt: 1,
        fields: const {
          'content': FieldValue('remote-old', 200), // 旧，应被忽略
          'mood': FieldValue('excited', 200),        // 新，应覆盖
        },
      );
      final merged = mergeSyncEntry(local, incoming);
      expect(merged['content'], const FieldValue('local-new', 300));
      expect(merged['mood'], const FieldValue('excited', 200));
    });
  });
}
