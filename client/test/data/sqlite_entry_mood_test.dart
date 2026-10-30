import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late SqliteEntryRepository repo;

  Entry _entry(String id, String content) => Entry(
    id: id, content: content,
    createdAt: DateTime.utc(2026, 10, 30, 2, 0),
    updatedAt: DateTime.utc(2026, 10, 30, 2, 0),
    dayKey: '2026-10-30',
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('local_diary_mood_');
    repo = SqliteEntryRepository(
      factory: databaseFactoryFfi,
      path: '${temp.path}/journal.db',
    );
  });

  tearDown(() async {
    await repo.close();
    Object? cleanupError;
    try {
      await temp.delete(recursive: true);
    } catch (error) {
      // Windows 上偶发文件句柄占用，删不掉就留下路径，便于手工清理。
      debugPrint('删除临时目录失败: ${temp.path} ($error)');
      cleanupError = error;
    }
    // 清理失败不能被静默吞掉：断言无异常，测试要红，否则临时目录会一直堆积。
    expect(cleanupError, isNull, reason: '临时目录清理失败: ${temp.path}');
  });

  test('v3 库的 entries 表含 mood 列', () async {
    await repo.save(_entry('a', '正文'));
    final all = await repo.exportAll();
    expect(all.single.mood, isNull); // mood 列可读，新条目为 null
  });

  test('迁移幂等：重复打开同一库不因 mood 列撞名', () async {
    await repo.save(_entry('a', '正文'));
    await repo.close();
    repo = SqliteEntryRepository(
      factory: databaseFactoryFfi,
      path: '${temp.path}/journal.db',
    );
    final all = await repo.exportAll();
    expect(all.single.content, '正文'); // 老数据完好
  });
}
