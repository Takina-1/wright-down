import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';
import 'package:local_diary/src/ui/sync/sync_status_indicator.dart';

void main() {
  testWidgets('syncing 显示 ⟳ 与「同步中」', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SyncStatusIndicator(state: SyncState.syncing)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('同步中'), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
  });

  testWidgets('synced 显示 ✓ 与「已同步」', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SyncStatusIndicator(state: SyncState.synced)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已同步'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('failed 显示 ⚠ 与「同步失败」', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SyncStatusIndicator(state: SyncState.failed)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('同步失败'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
  });

  testWidgets('idle 显示本地模式文案', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SyncStatusIndicator(state: SyncState.idle)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('本地模式'), findsOneWidget);
  });
}
