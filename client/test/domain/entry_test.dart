import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';

void main() {
  group('Entry', () {
    test('默认没有删除时间', () {
      final entry = Entry(
        id: 'a',
        content: '正文',
        createdAt: DateTime.utc(2026, 10, 28),
        updatedAt: DateTime.utc(2026, 10, 28),
        dayKey: '2026-10-28',
      );
      expect(entry.deletedAt, isNull);
      expect(entry.isDeleted, isFalse);
    });

    test('带删除时间时视为已删除', () {
      final entry = Entry(
        id: 'a',
        content: '正文',
        createdAt: DateTime.utc(2026, 10, 28),
        updatedAt: DateTime.utc(2026, 10, 28),
        dayKey: '2026-10-28',
        deletedAt: DateTime.utc(2026, 10, 30),
      );
      expect(entry.isDeleted, isTrue);
      expect(entry.deletedAt, DateTime.utc(2026, 10, 30));
    });

    test('dayKey 合法性判断', () {
      expect(isValidDayKey('2026-10-28'), isTrue);
      expect(isValidDayKey('2026-1-8'), isFalse);
      expect(isValidDayKey('2026'), isFalse);
      expect(isValidDayKey(''), isFalse);
    });
  });
}
