import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/timeline_page.dart';

import '../support/memory_repository.dart';

void main() {
  final created = DateTime.utc(2026, 10, 28, 8);

  testWidgets('a short day key does not break the timeline', (tester) async {
    final repo = MemoryRepository();
    // 历史脏数据：早期版本或手工改过的备份可能留下长度不足的 dayKey。
    repo.entries['dirty'] = Entry(
      id: 'dirty',
      content: '一条 dayKey 不合法的旧记录',
      createdAt: created,
      updatedAt: created,
      dayKey: '2026',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePage(repository: repo, onEdit: (_) {}, onStart: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 页面能打开，条目本身仍然读得到。
    expect(tester.takeException(), isNull);
    expect(find.text('一条 dayKey 不合法的旧记录'), findsOneWidget);
    // 月份标题退回用创建时间的本地年月，不抛 RangeError。
    expect(find.textContaining('月'), findsWidgets);
  });
}
