import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/app.dart';
import 'package:local_diary/src/domain/export/file_gateway.dart';
import 'package:local_diary/src/ui/export_page.dart';
import 'package:local_diary/src/ui/local_data_page.dart';

import '../support/memory_repository.dart';

/// 只记录调用的文件出口，用来验证出口确实被传到了导出页。
class RecordingFileGateway implements FileGateway {
  final List<String> savedNames = [];

  @override
  Future<String?> saveFile({
    required String suggestedName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    savedNames.add(suggestedName);
    return 'content://fake/$suggestedName';
  }

  @override
  Future<Uint8List?> pickFile({
    required String mimeType,
    required List<String> extensions,
  }) async => null;

  @override
  Future<void> shareFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {}
}

void main() {
  testWidgets('the mine page opens the export and backup page', (tester) async {
    final repo = MemoryRepository();
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tab-mine')));
    await tester.pumpAndSettle();

    expect(find.text('导出与备份'), findsOneWidget);
    expect(find.text('本地数据说明'), findsOneWidget);

    await tester.tap(find.text('导出与备份'));
    await tester.pumpAndSettle();

    // 导出页真的被推上来了。
    expect(find.byType(ExportPage), findsOneWidget);
    expect(find.text('导出与备份'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('export-plaintext-note'))).data,
      contains('明文'),
    );

    // 仓储是同一个实例，没有在跳转时被换掉。
    final exportPage = tester.widget<ExportPage>(find.byType(ExportPage));
    expect(exportPage.repository, same(repo));
  });

  testWidgets('the mine page hands its file gateway to the export page', (
    tester,
  ) async {
    final repo = MemoryRepository();
    final gateway = RecordingFileGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDataPage(repository: repo, fileGateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('导出与备份'));
    await tester.pumpAndSettle();

    final exportPage = tester.widget<ExportPage>(find.byType(ExportPage));
    expect(exportPage.fileGateway, same(gateway));
    expect(exportPage.repository, same(repo));

    await tester.tap(find.text('导出备份（可恢复）'));
    await tester.pumpAndSettle();

    // 注入的出口真的被用上了。
    expect(gateway.savedNames, hasLength(1));
    expect(find.text('已导出 0 条'), findsOneWidget);
  });

  testWidgets('the local data note says backups are plaintext to keep safe', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LocalDataPage(repository: MemoryRepository())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('本地数据说明'));
    await tester.pumpAndSettle();

    final note = tester.widget<Text>(find.byKey(const Key('local-data-note')));
    expect(note.data, contains('备份文件'));
    expect(note.data, contains('Markdown'));
    expect(note.data, contains('明文'));
    expect(note.data, contains('不做加密'));
    expect(note.data, contains('自行保管'));
    // 强制终止可能丢失最近输入的风险告知不能因为加了导出功能而消失。
    expect(note.data, contains('尚未保存时强制终止应用可能丢失最近输入'));
    expect(note.data, isNot(contains('尚未提供导出与备份')));
  });
}
