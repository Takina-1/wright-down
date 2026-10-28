import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/app.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('PROBE C1c: failing save + back press during transition', (
    tester,
  ) async {
    final repo = MemoryRepository()..failSave = true;
    final gate = Completer<void>();
    repo.gate = gate;
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.enterText(find.byKey(const Key('entry-content')), '未保存内容');
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pump(); // _transitioning == true, flush pending on gate
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    debugPrint('PROBE C1c navEnabledDuringTransition=${nav.onDestinationSelected != null}');
    await tester.binding.handlePopRoute();
    await tester.pump();
    debugPrint(
      'PROBE C1c dialogAfterBackDuringTransition=${find.text('还有未保存的内容').evaluate().isNotEmpty}',
    );
    gate.complete(); // now the pending flush fails
    await tester.pumpAndSettle();
    debugPrint(
      'PROBE C1c dialogAfterGateReleased=${find.text('还有未保存的内容').evaluate().isNotEmpty}',
    );
    debugPrint(
      'PROBE C1c composerStillVisible=${find.byKey(const Key('entry-content')).evaluate().isNotEmpty}',
    );
    // Now press back again, outside of any transition: the dialog should appear.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    debugPrint(
      'PROBE C1c dialogAfterSecondBack=${find.text('还有未保存的内容').evaluate().isNotEmpty}',
    );
  });

  testWidgets('PROBE C1d: unmount during _selectTab leaves _transitioning true', (
    tester,
  ) async {
    final repo = MemoryRepository();
    final gate = Completer<void>();
    repo.gate = gate;
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.enterText(find.byKey(const Key('entry-content')), '未保存内容');
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pump();
    // Unmount HomePage entirely.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    // Re-mount a fresh HomePage: does it come back with _transitioning stuck?
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.pumpAndSettle();
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    debugPrint('PROBE C1d freshNavEnabled=${nav.onDestinationSelected != null}');
    final tf = tester.widget<TextField>(find.byKey(const Key('entry-content')));
    debugPrint('PROBE C1d freshTextFieldReadOnly=${tf.readOnly}');
  });
}
