import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/app.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/local_entry_repository.dart';

/// A repository with a realistically slow write (like a real SQLite transaction).
class SlowRepository implements LocalEntryRepository {
  final Map<String, Entry> entries = {};
  int delayMs;
  bool failSave = false;
  SlowRepository(this.delayMs);
  @override
  Future<void> save(Entry entry) async {
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    if (failSave) throw StateError('disk failure');
    entries[entry.id] = entry;
  }

  @override
  Future<List<Entry>> list({EntryCursor? before, int limit = 30}) async => const [];
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('PROBE C1e: slow (200ms) save, back press at t=50ms', (
    tester,
  ) async {
    final repo = SlowRepository(200);
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.enterText(find.byKey(const Key('entry-content')), '重要的文字');
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pump(); // t=0, flush in flight, _transitioning == true
    await tester.pump(const Duration(milliseconds: 50)); // t=50ms
    await tester.binding.handlePopRoute();
    await tester.pump();
    debugPrint(
      'PROBE C1e navEnabledAt50ms=${tester.widget<NavigationBar>(find.byType(NavigationBar)).onDestinationSelected != null}',
    );
    debugPrint(
      'PROBE C1e stillOnComposerAt50ms=${find.byKey(const Key('entry-content')).evaluate().isNotEmpty}',
    );
    // let the slow save finish
    await tester.pumpAndSettle();
    debugPrint('PROBE C1e savedAfterTransition=${repo.entries.values.single.content}');
    debugPrint(
      'PROBE C1e onReviewTabAfterTransition=${find.byKey(const Key('tab-review')).evaluate().isNotEmpty}',
    );
    // second back press, now that no transition is in flight
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    debugPrint(
      'PROBE C1e dialogOnSecondBack=${find.text('还有未保存的内容').evaluate().isNotEmpty}',
    );
  });

  testWidgets('PROBE C1f: slow save that FAILS, back press mid-flight', (
    tester,
  ) async {
    final repo = SlowRepository(200)..failSave = true;
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.enterText(find.byKey(const Key('entry-content')), '会丢失的文字');
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.binding.handlePopRoute();
    await tester.pump();
    debugPrint(
      'PROBE C1f dialogMidFlight=${find.text('还有未保存的内容').evaluate().isNotEmpty}',
    );
    await tester.pumpAndSettle();
    debugPrint(
      'PROBE C1f errorShownAfterFail=${find.text('保存失败').evaluate().isNotEmpty}',
    );
    debugPrint(
      'PROBE C1f textPreserved=${find.text('会丢失的文字').evaluate().isNotEmpty}',
    );
  });
}
