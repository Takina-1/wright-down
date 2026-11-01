import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/backup_codec.dart';

Entry _entry(String id, [Uint8List? photo]) => Entry(
  id: id,
  content: '正文 $id',
  createdAt: DateTime.utc(2026, 10, 30, 2, 0),
  updatedAt: DateTime.utc(2026, 10, 30, 2, 0),
  dayKey: '2026-10-30',
  photo: photo,
);

void main() {
  const codec = BackupCodec();

  test('AC-08: 带照片的条目编码后解码能读回 photo', () {
    final bytes = Uint8List.fromList([1, 2, 3, 255, 0, 128]);
    final text = codec.encode([_entry('e1', bytes)]);
    final decoded = codec.decode(text).entries.single.photo;
    expect(decoded, isNotNull);
    expect(decoded!.length, 6);
    for (var i = 0; i < bytes.length; i++) {
      expect(decoded[i], bytes[i]);
    }
  });

  test('未配照片的条目不写 photo 键，解码为 null', () {
    final text = codec.encode([_entry('e2')]);
    expect(text, isNot(contains('"photo"')));
    expect(codec.decode(text).entries.single.photo, isNull);
  });

  test('带照片的条目编码文本里含 photo 键（base64）', () {
    final text = codec.encode([_entry('e3', Uint8List.fromList([10, 20, 30]))]);
    // JSON 编码器在冒号后带空格，不锁死空格，只锁键与 base64 值。
    expect(text, contains('"photo"'));
    // base64Encode 输出的是编码串本身，不含 "base64" 字样；解码它能还原。
    final decoded = codec.decode(text).entries.single.photo;
    expect(decoded, isA<Uint8List>());
    expect(decoded!.length, 3);
  });

  test('AC-07: 旧 v3 备份（无 photo 键）解码为 null，不报错', () {
    const old = '''{
  "format": "local-diary-backup",
  "version": 3,
  "exportedAt": "2026-10-30T02:00:00.000Z",
  "entryCount": 1,
  "entries": [{
    "id": "e4",
    "content": "旧记录",
    "createdAt": "2026-10-30T02:00:00.000Z",
    "updatedAt": "2026-10-30T02:00:00.000Z",
    "dayKey": "2026-10-30"
  }]
}''';
    expect(codec.decode(old).entries.single.photo, isNull);
  });

  test('photo 存在但非字符串（如数字）判损坏，抛 BackupFormatException', () {
    const damaged = '''{
  "format": "local-diary-backup",
  "version": 3,
  "exportedAt": "2026-10-30T02:00:00.000Z",
  "entryCount": 1,
  "entries": [{
    "id": "e5",
    "content": "损坏记录",
    "createdAt": "2026-10-30T02:00:00.000Z",
    "updatedAt": "2026-10-30T02:00:00.000Z",
    "dayKey": "2026-10-30",
    "photo": 123
  }]
}''';
    expect(
      () => codec.decode(damaged),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.reason,
          'reason',
          BackupCodec.damagedReason,
        ),
      ),
    );
  });

  test('photo 是非合法 base64 字符串判损坏，抛 BackupFormatException', () {
    const damaged = '''{
  "format": "local-diary-backup",
  "version": 3,
  "exportedAt": "2026-10-30T02:00:00.000Z",
  "entryCount": 1,
  "entries": [{
    "id": "e6",
    "content": "损坏记录",
    "createdAt": "2026-10-30T02:00:00.000Z",
    "updatedAt": "2026-10-30T02:00:00.000Z",
    "dayKey": "2026-10-30",
    "photo": "这不是合法base64!!!"
  }]
}''';
    expect(
      () => codec.decode(damaged),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.reason,
          'reason',
          BackupCodec.damagedReason,
        ),
      ),
    );
  });
}
