import 'package:test/test.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  group('FieldValue', () {
    test('相等比较按 v 与 t', () {
      expect(const FieldValue('a', 1), const FieldValue('a', 1));
      expect(const FieldValue('a', 1), isNot(const FieldValue('b', 1)));
      expect(const FieldValue('a', 1), isNot(const FieldValue('a', 2)));
    });

    test('v 可为 null（mood/photo/deletedAt 用）', () {
      expect(const FieldValue(null, 1).v, isNull);
    });
  });

  group('SyncEntry', () {
    test('持有 id、createdAt 与字段映射', () {
      final e = SyncEntry(
        id: 'e1',
        createdAt: 1000,
        fields: const {'content': FieldValue('hi', 2000)},
      );
      expect(e.id, 'e1');
      expect(e.createdAt, 1000);
      expect(e.fields['content']?.v, 'hi');
      expect(e.fields['content']?.t, 2000);
    });
  });
}
