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
    // 备份格式已升到版本 2。
    expect(decoded.version, 2);
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
      () => codec.decode(
        '{"format":"local-diary-backup","version":3,"entries":[]}',
      ),
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
    const broken =
        '{"format":"local-diary-backup","version":1,'
        '"exportedAt":"2026-10-28T08:00:00.000Z",'
        '"entryCount":1,'
        '"entries":[{"id":"a","content":"正文",'
        '"createdAt":"2026-10-28T08:00:00.000Z",'
        '"updatedAt":"2026-10-28T08:00:00.000Z"}]}';
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

  test('a backup without an export time is reported as damaged', () {
    const broken =
        '{"format":"local-diary-backup","version":1,'
        '"entryCount":1,'
        '"entries":[{"id":"a","content":"正文",'
        '"createdAt":"2026-10-28T08:00:00.000Z",'
        '"updatedAt":"2026-10-28T08:00:00.000Z",'
        '"dayKey":"2026-10-28"}]}';
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
    const broken =
        '{"format":"local-diary-backup","version":1,'
        '"exportedAt":"2026-10-28T08:00:00.000Z",'
        '"entryCount":1,'
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

  test('a backup with duplicated ids is reported as damaged', () {
    const duplicated =
        '{"format":"local-diary-backup","version":1,'
        '"exportedAt":"2026-10-28T08:00:00.000Z",'
        '"entryCount":2,'
        '"entries":[{"id":"a","content":"正文",'
        '"createdAt":"2026-10-28T08:00:00.000Z",'
        '"updatedAt":"2026-10-28T08:00:00.000Z",'
        '"dayKey":"2026-10-28"},'
        '{"id":"a","content":"另一条正文",'
        '"createdAt":"2026-10-28T08:00:00.000Z",'
        '"updatedAt":"2026-10-28T08:00:00.000Z",'
        '"dayKey":"2026-10-28"}]}';
    expect(
      () => codec.decode(duplicated),
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
    const empty =
        '{"format":"local-diary-backup","version":1,'
        '"exportedAt":"2026-10-28T08:00:00.000Z",'
        '"entryCount":1,'
        '"entries":[{"id":"a","content":"","createdAt":"2026-10-28T08:00:00.000Z",'
        '"updatedAt":"2026-10-28T08:00:00.000Z","dayKey":"2026-10-28"}]}';
    const whitespace =
        '{"format":"local-diary-backup","version":1,'
        '"exportedAt":"2026-10-28T08:00:00.000Z",'
        '"entryCount":1,'
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

  test('an entry with a malformed day key is reported as damaged', () {
    // 其余字段全部合法，失败原因唯一指向 dayKey 的格式。
    String backupWith(String dayKey) =>
        '{"format":"local-diary-backup","version":1,'
        '"exportedAt":"2026-10-28T08:00:00.000Z",'
        '"entryCount":1,'
        '"entries":[{"id":"a","content":"正文",'
        '"createdAt":"2026-10-28T08:00:00.000Z",'
        '"updatedAt":"2026-10-28T08:00:00.000Z",'
        '"dayKey":"$dayKey"}]}';

    for (final bad in ['2026', 'x', '2026-10', '2026-10-28T00:00:00Z']) {
      expect(
        () => codec.decode(backupWith(bad)),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.reason,
            'reason',
            '备份文件已损坏，无法恢复',
          ),
        ),
        reason: 'dayKey "$bad" 必须被整体拒绝',
      );
    }
  });

  group('备份格式版本 2', () {
    test('已删除条目编码后带 deletedAt，解码后能读回', () {
      final codec = BackupCodec();
      final deleted = Entry(
        id: 'a',
        content: '写错了',
        createdAt: DateTime.utc(2026, 10, 28, 3),
        updatedAt: DateTime.utc(2026, 10, 30, 1),
        dayKey: '2026-10-28',
        deletedAt: DateTime.utc(2026, 10, 30, 1),
      );
      final live = Entry(
        id: 'b',
        content: '正常记录',
        createdAt: DateTime.utc(2026, 10, 29, 3),
        updatedAt: DateTime.utc(2026, 10, 29, 3),
        dayKey: '2026-10-29',
      );

      final text = codec.encode([deleted, live]);
      expect(text, contains('"version": 2'));
      expect(text, contains('deletedAt'));

      final document = codec.decode(text);
      expect(document.version, 2);
      expect(document.entries, hasLength(2));
      expect(document.entries.first.deletedAt, DateTime.utc(2026, 10, 30, 1));
      expect(document.entries.last.deletedAt, isNull);
    });

    test('version 1 的旧备份仍可导入，且条目一律视为未删除', () {
      const legacy = '''{
        "format": "local-diary-backup",
        "version": 1,
        "exportedAt": "2026-10-28T02:00:00.000Z",
        "entryCount": 1,
        "entries": [
          {
            "id": "old-1",
            "content": "旧版本写的记录",
            "createdAt": "2026-10-28T02:00:00.000Z",
            "updatedAt": "2026-10-28T02:00:00.000Z",
            "dayKey": "2026-10-28"
          }
        ]
      }''';
      final document = const BackupCodec().decode(legacy);
      expect(document.version, 1);
      expect(document.entries.single.deletedAt, isNull);
    });

    test('version 为 0 判损坏', () {
      expect(
        () => const BackupCodec().decode(
          '{"format":"local-diary-backup","version":0,'
          '"exportedAt":"2026-10-28T02:00:00.000Z","entryCount":0,"entries":[]}',
        ),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('version 高于当前支持时提示升级', () {
      expect(
        () => const BackupCodec().decode(
          '{"format":"local-diary-backup","version":3,'
          '"exportedAt":"2026-10-28T02:00:00.000Z","entryCount":0,"entries":[]}',
        ),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.reason,
            'reason',
            '备份来自更新的版本，请先升级应用',
          ),
        ),
      );
    });

    test('entryCount 与实际条数不符判损坏', () {
      expect(
        () => const BackupCodec().decode(
          '{"format":"local-diary-backup","version":2,'
          '"exportedAt":"2026-10-28T02:00:00.000Z","entryCount":9,"entries":[]}',
        ),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('时间串缺时区偏移判损坏', () {
      expect(
        () => const BackupCodec().decode(
          '{"format":"local-diary-backup","version":2,'
          '"exportedAt":"2026-10-28T02:00:00","entryCount":0,"entries":[]}',
        ),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('未删除的条目不写 deletedAt 键', () {
      final text = const BackupCodec().encode([
        Entry(
          id: 'live',
          content: '还活着',
          createdAt: DateTime.utc(2026, 10, 29, 3),
          updatedAt: DateTime.utc(2026, 10, 29, 3),
          dayKey: '2026-10-29',
        ),
      ]);
      expect(text, isNot(contains('deletedAt')));
    });

    test('entryCount 缺失判损坏', () {
      expect(
        () => const BackupCodec().decode(
          '{"format":"local-diary-backup","version":2,'
          '"exportedAt":"2026-10-28T02:00:00.000Z","entries":[]}',
        ),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('条目数据不完整时拒绝导出', () {
      final broken = Entry(
        id: '',
        content: '正文',
        createdAt: DateTime.utc(2026, 10, 28, 3),
        updatedAt: DateTime.utc(2026, 10, 28, 3),
        dayKey: '2026-10-28',
      );
      expect(
        () => const BackupCodec().encode([broken]),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.reason,
            'reason',
            '有条记录数据不完整，无法导出',
          ),
        ),
      );
    });

    test('条目正文全为空白时拒绝导出', () {
      expect(
        () => const BackupCodec().encode([
          Entry(
            id: 'a',
            content: '   \n  ',
            createdAt: DateTime.utc(2026, 10, 28, 3),
            updatedAt: DateTime.utc(2026, 10, 28, 3),
            dayKey: '2026-10-28',
          ),
        ]),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.reason,
            'reason',
            '有条记录数据不完整，无法导出',
          ),
        ),
      );
    });

    test('解码后的条目列表不可修改', () {
      final document = const BackupCodec().decode(
        '{"format":"local-diary-backup","version":2,'
        '"exportedAt":"2026-10-28T02:00:00.000Z","entryCount":1,'
        '"entries":[{"id":"a","content":"正文",'
        '"createdAt":"2026-10-28T02:00:00.000Z",'
        '"updatedAt":"2026-10-28T02:00:00.000Z","dayKey":"2026-10-28"}]}',
      );
      expect(
        () => document.entries.add(
          Entry(
            id: 'b',
            content: '偷加的一条',
            createdAt: DateTime.utc(2026, 10, 29),
            updatedAt: DateTime.utc(2026, 10, 29),
            dayKey: '2026-10-29',
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('JSON 缺右括号时按损坏处理', () {
      expect(
        () => const BackupCodec().decode('{"format":"local-diary-backup",'),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.reason,
            'reason',
            '这不是本应用的备份文件',
          ),
        ),
      );
    });
  });
}
