import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/backup_codec.dart';

Entry _entry(String id, [String? mood]) => Entry(
  id: id, content: '正文 $id',
  createdAt: DateTime.utc(2026, 10, 30, 2, 0),
  updatedAt: DateTime.utc(2026, 10, 30, 2, 0),
  dayKey: '2026-10-30', mood: mood,
);

void main() {
  const codec = BackupCodec();

  test('带 mood 的条目编码后解码能读回 mood', () {
    final text = codec.encode([_entry('e1', 'happy')]);
    expect(codec.decode(text).entries.single.mood, 'happy');
  });

  test('未设心情的条目不写 mood 键，解码为 null', () {
    final text = codec.encode([_entry('e2')]);
    expect(text, isNot(contains('"mood"')));
    expect(codec.decode(text).entries.single.mood, isNull);
  });

  test('带 mood 的条目编码文本里含 mood 键', () {
    final text = codec.encode([_entry('e3', 'sad')]);
    expect(text, contains('"mood": "sad"'));
  });

  test('旧 v2 备份（无 mood 键）解码为 null，不报错', () {
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
    expect(codec.decode(old).entries.single.mood, isNull);
  });
}
