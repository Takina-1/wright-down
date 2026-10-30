import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/app.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/backup_codec.dart';
import 'package:local_diary/src/domain/export/file_gateway.dart';
import 'package:local_diary/src/ui/export_page.dart';

import '../support/memory_repository.dart';

class FakeFileGateway implements FileGateway {
  Uint8List? pickResult;
  String? sharedName;
  String? savedName;

  @override
  Future<String?> saveFile({
    required String suggestedName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    savedName = suggestedName;
    return 'content://fake/$suggestedName';
  }

  @override
  Future<Uint8List?> pickFile({
    required String mimeType,
    required List<String> extensions,
  }) async {
    return pickResult;
  }

  @override
  Future<void> shareFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    sharedName = fileName;
  }
}

void main() {
  final time = DateTime.utc(2026, 10, 28, 8);
  Entry entry(String id, String content) => Entry(
    id: id,
    content: content,
    createdAt: time,
    updatedAt: time,
    dayKey: '2026-10-28',
  );

  testWidgets('the page explains that both exports are plaintext', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(
          repository: MemoryRepository(),
          fileGateway: FakeFileGateway(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final note = tester.widget<Text>(
      find.byKey(const Key('export-plaintext-note')),
    );
    expect(note.data, contains('备份文件'));
    expect(note.data, contains('Markdown'));
    expect(note.data, contains('明文'));
    expect(note.data, contains('不做加密'));
  });

  testWidgets('exporting a backup shows the exported count', (tester) async {
    final repo = MemoryRepository();
    repo.entries['a'] = entry('a', '第一条');
    final gateway = FakeFileGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(repository: repo, fileGateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('导出备份（可恢复）'));
    await tester.pumpAndSettle();

    expect(find.text('已导出 1 条'), findsOneWidget);
    expect(gateway.savedName, endsWith('.json'));
  });

  testWidgets('a saved export can be shared from the page', (tester) async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(repository: repo, fileGateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('导出 Markdown（可阅读）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享'));
    await tester.pumpAndSettle();

    expect(gateway.sharedName, endsWith('.md'));
  });

  testWidgets('restoring asks for confirmation before touching the journal', (
    tester,
  ) async {
    final repo = MemoryRepository();
    final backup = const BackupCodec().encode([
      entry('b', '备份新增'),
    ], exportedAt: time);
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(utf8.encode(backup));
    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(repository: repo, fileGateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('从备份恢复'));
    await tester.pumpAndSettle();

    expect(find.textContaining('新增 1 条'), findsOneWidget);
    expect(repo.entries, isEmpty);

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(repo.entries['b']!.content, '备份新增');
    expect(find.textContaining('恢复完成'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation leaves the journal untouched', (
    tester,
  ) async {
    final repo = MemoryRepository();
    final backup = const BackupCodec().encode([
      entry('c', '不该写入'),
    ], exportedAt: time);
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(utf8.encode(backup));
    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(repository: repo, fileGateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('从备份恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(repo.entries, isEmpty);
    expect(find.textContaining('恢复完成'), findsNothing);
    expect(find.textContaining('失败'), findsNothing);
  });

  testWidgets('a broken backup shows the reason and changes nothing', (
    tester,
  ) async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(utf8.encode('不是备份'));
    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(repository: repo, fileGateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('从备份恢复'));
    await tester.pumpAndSettle();

    expect(find.text(BackupCodec.notOurBackupReason), findsOneWidget);
    expect(repo.entries, isEmpty);
  });

  testWidgets('a restored entry shows up in the review timeline', (
    tester,
  ) async {
    final repo = MemoryRepository();
    final backup = const BackupCodec().encode([
      Entry(
        id: 'restored',
        content: '从备份恢复出来的一条',
        createdAt: time,
        updatedAt: time,
        dayKey: '2026-10-28',
      ),
    ], exportedAt: time);
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(utf8.encode(backup));

    await tester.pumpWidget(JournalApp(repository: repo, fileGateway: gateway));
    await tester.pumpAndSettle();

    // 「我的」→ 「导出与备份」→ 触发恢复并确认。
    await tester.tap(find.byKey(const Key('tab-mine')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出与备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从备份恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(repo.entries['restored'], isNotNull);

    // 返回上一级，再切到「回顾」，恢复的条目要读得到。
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();

    expect(find.text('从备份恢复出来的一条'), findsOneWidget);
  });
}
