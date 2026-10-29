import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/ui/local_data_page.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('the mine page offers the export and backup entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDataPage(repository: MemoryRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('导出与备份'), findsOneWidget);
    expect(find.text('本地数据说明'), findsOneWidget);
  });

  testWidgets('the local data note says backups are plaintext to keep safe', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDataPage(repository: MemoryRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('本地数据说明'));
    await tester.pumpAndSettle();

    expect(find.textContaining('明文'), findsOneWidget);
    expect(find.textContaining('自行保管'), findsOneWidget);
    expect(find.textContaining('尚未提供导出与备份'), findsNothing);
  });
}
