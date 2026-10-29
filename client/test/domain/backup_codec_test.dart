import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/backup_codec.dart';

void main() {
  const codec = BackupCodec();
  final created = DateTime.utc(2026, 10, 28, 8);
  Entry entry(String id, String content) => Entry(
    id: id,
    content: content,
    createdAt: created,
    updatedAt: created.add(const Duration(minutes: 5)),
    dayKey: '2026-10-28',
  );

  test('a decoded backup keeps every field of the original entry', () {
    final original = entry('a', '今天走了很远。\n明天继续 🌿');
    final text = codec.encode([original], exportedAt: created);
    final decoded = codec.decode(text);
    expect(decoded.version, 1);
    expect(decoded.exportedAt, created);
    expect(decoded.entries, hasLength(1));
    expect(decoded.entries.single.id, 'a');
    expect(decoded.entries.single.content, '今天走了很远。\n明天继续 🌿');
    expect(decoded.entries.single.createdAt, original.createdAt);
    expect(decoded.entries.single.updatedAt, original.updatedAt);
    expect(decoded.entries.single.dayKey, '2026-10-28');
  });

  test('an empty journal still encodes into a valid backup', () {
    final text = codec.encode(const [], exportedAt: created);
    final decoded = codec.decode(text);
    expect(decoded.entries, isEmpty);
    expect(text, contains('"entryCount": 0'));
  });

  test('a file that is not json is rejected as a foreign backup', () {
    expect(
      () => codec.decode('这不是 json'),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.reason,
          'reason',
          '这不是本应用的备份文件',
        ),
      ),
    );
  });

  test('a json file from another app is rejected', () {
    expect(
      () => codec.decode('{"format":"other-app","version":1,"entries":[]}'),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.reason,
          'reason',
          '这不是本应用的备份文件',
        ),
      ),
    );
  });

  test('a newer backup version asks the user to update the app', () {
    expect(
      () => codec.decode('{"format":"local-diary-backup","version":2,"entries":[]}'),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.reason,
          'reason',
          '备份来自更新的版本，请先升级应用',
        ),
      ),
    );
  });

  test('an entry with a missing field is reported as damaged', () {
    const broken = '{"format":"local-diary-backup","version":1,'
        '"exportedAt":"2026-10-28T08:00:00.000Z",'
        '"entries":[{"id":"a","content":"正文"}]}';
    expect(
      () => codec.decode(broken),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.reason,
          'reason',
          '备份文件已损坏，无法恢复',
        ),
      ),
    );
  });

  test('an entry with a wrong field type is reported as damaged', () {
    const broken = '{"format":"local-diary-backup","version":1,'
        '"exportedAt":"2026-10-28T08:00:00.000Z",'
        '"entries":[{"id":"a","content":42,"createdAt":"2026-10-28T08:00:00.000Z",'
        '"updatedAt":"2026-10-28T08:00:00.000Z","dayKey":"2026-10-28"}]}';
    expect(
      () => codec.decode(broken),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.reason,
          'reason',
          '备份文件已损坏，无法恢复',
        ),
      ),
    );
  });

  test('an entry with blank content is reported as damaged', () {
    const empty = '{"format":"local-diary-backup","version":1,'
        '"exportedAt":"2026-10-28T08:00:00.000Z",'
        '"entries":[{"id":"a","content":"","createdAt":"2026-10-28T08:00:00.000Z",'
        '"updatedAt":"2026-10-28T08:00:00.000Z","dayKey":"2026-10-28"}]}';
    const whitespace = '{"format":"local-diary-backup","version":1,'
        '"exportedAt":"2026-10-28T08:00:00.000Z",'
        '"entries":[{"id":"a","content":"   \\n  ","createdAt":"2026-10-28T08:00:00.000Z",'
        '"updatedAt":"2026-10-28T08:00:00.000Z","dayKey":"2026-10-28"}]}';
    for (final broken in [empty, whitespace]) {
      expect(
        () => codec.decode(broken),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.reason,
            'reason',
            '备份文件已损坏，无法恢复',
          ),
        ),
      );
    }
  });
}
