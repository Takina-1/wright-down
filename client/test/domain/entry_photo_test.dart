import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';

void main() {
  test('AC-09: 无照片时 photo 为 null', () {
    final e = Entry(
      id: 'a',
      content: '正文',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
      dayKey: '2026-10-28',
    );
    expect(e.photo, isNull);
  });

  test('AC-09: 有照片时 photo 保留原始字节', () {
    final bytes = Uint8List.fromList([1, 2, 3, 255, 0, 128]);
    final e = Entry(
      id: 'a',
      content: '正文',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
      dayKey: '2026-10-28',
      photo: bytes,
    );
    expect(e.photo, isNotNull);
    expect(e.photo!.length, 6);
    // Uint8List 逐字节比较。
    for (var i = 0; i < bytes.length; i++) {
      expect(e.photo![i], bytes[i]);
    }
  });

  test('AC-09: photo 是 Uint8List（可存 BLOB）', () {
    final e = Entry(
      id: 'a',
      content: '正文',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
      dayKey: '2026-10-28',
      photo: Uint8List.fromList([10, 20]),
    );
    expect(e.photo, isA<Uint8List>());
  });
}
