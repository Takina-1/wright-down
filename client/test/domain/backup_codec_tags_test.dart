import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/backup_codec.dart';

Entry _entry(String id, [List<String> tags = const []]) => Entry(
  id: id,
  content: '正文 $id',
  createdAt: DateTime.utc(2026, 10, 30, 2, 0),
  updatedAt: DateTime.utc(2026, 10, 30, 2, 0),
  dayKey: '2026-10-30',
  tags: tags,
);

void main() {
  const codec = BackupCodec();

  test('AC-08: 带标签的条目编码后解码能读回 tags', () {
    final text = codec.encode([_entry('e1', ['旅行', '读书'])]);
    expect(codec.decode(text).entries.single.tags, ['旅行', '读书']);
  });

  test('未设标签的条目不写 tags 键，解码为空列表', () {
    final text = codec.encode([_entry('e2')]);
    expect(text, isNot(contains('"tags"')));
    expect(codec.decode(text).entries.single.tags, isEmpty);
  });

  test('带标签的条目编码文本里含 tags 键', () {
    final text = codec.encode([_entry('e3', ['旅行'])]);
    // JSON 编码器在冒号后带空格（"tags": [...]），不锁死空格，只锁键与值。
    expect(text, contains('"tags"'));
    expect(text, contains('旅行'));
  });

  test('AC-07: 旧 v2 备份（无 tags 键）解码为空列表，不报错', () {
    const old = '''{
  "format": "local-diary-backup",
  "version": 2,
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
    expect(codec.decode(old).entries.single.tags, isEmpty);
  });

  test('tags 存在但非字符串数组（如字符串）判损坏，抛 BackupFormatException', () {
    const damaged = '''{
  "format": "local-diary-backup",
  "version": 2,
  "exportedAt": "2026-10-30T02:00:00.000Z",
  "entryCount": 1,
  "entries": [{
    "id": "e5",
    "content": "损坏记录",
    "createdAt": "2026-10-30T02:00:00.000Z",
    "updatedAt": "2026-10-30T02:00:00.000Z",
    "dayKey": "2026-10-30",
    "tags": "不是数组"
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

  test('tags 数组含非字符串元素判损坏，抛 BackupFormatException', () {
    const damaged = '''{
  "format": "local-diary-backup",
  "version": 2,
  "exportedAt": "2026-10-30T02:00:00.000Z",
  "entryCount": 1,
  "entries": [{
    "id": "e6",
    "content": "损坏记录",
    "createdAt": "2026-10-30T02:00:00.000Z",
    "updatedAt": "2026-10-30T02:00:00.000Z",
    "dayKey": "2026-10-30",
    "tags": ["旅行", 123]
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
