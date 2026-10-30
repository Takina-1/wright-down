import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/timeline_page.dart';

import '../support/memory_repository.dart';

Entry _e(String id, [String? mood]) => Entry(
  id: id, content: '正文 $id',
  createdAt: DateTime.utc(2026, 10, 30, 2, 0),
  updatedAt: DateTime.utc(2026, 10, 30, 2, 0),
  dayKey: '2026-10-30', mood: mood,
);

Future<void> _pump(WidgetTester tester, MemoryRepository repo) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TimelinePage(repository: repo, onEdit: (_) {}, onStart: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('已设心情的卡片显示 emoji', (tester) async {
    final repo = MemoryRepository();
    repo.entries['e1'] = _e('e1', 'happy');
    await _pump(tester, repo);
    expect(find.text('😄'), findsOneWidget);
  });

  testWidgets('未设心情的卡片不显示心情 emoji', (tester) async {
    final repo = MemoryRepository();
    repo.entries['e2'] = _e('e2');
    await _pump(tester, repo);
    expect(find.text('😄'), findsNothing);
    expect(find.text('😊'), findsNothing);
    expect(find.text('😢'), findsNothing);
  });
}
