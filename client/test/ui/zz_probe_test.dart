import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/app.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('PROBE C1: back press during _transitioning is swallowed', (
    tester,
  ) async {
    final repo = MemoryRepository();
    final gate = Completer<void>();
    repo.gate = gate;
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.enterText(find.byKey(const Key('entry-content')), '未保存内容');
    // tap the review tab -> _selectTab sets _transitioning = true and awaits flush
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pump();
    // Now _transitioning is true (flush is blocked on the gate).
    // Simulate the system back press.
    await tester.binding.handlePopRoute();
    await tester.pump();
    // If the back press had been handled, the flush would be attempted /
    // the "还有未保存的内容" dialog would be shown on failure, or the app exits.
    final dialogShown = find.text('还有未保存的内容').evaluate().isNotEmpty;
    debugPrint('PROBE C1 dialogShown=$dialogShown');
    debugPrint(
      'PROBE C1 tabReviewVisible=${find.byKey(const Key('tab-review')).evaluate().isNotEmpty}',
    );
    debugPrint(
      'PROBE C1 composerVisible=${find.byKey(const Key('entry-content')).evaluate().isNotEmpty}',
    );
    // Also check the nav bar is disabled (onDestinationSelected == null while transitioning)
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    debugPrint('PROBE C1 navEnabled=${nav.onDestinationSelected != null}');
    gate.complete();
    await tester.pumpAndSettle();
    debugPrint(
      'PROBE C1 after settle composerVisible=${find.byKey(const Key('entry-content')).evaluate().isNotEmpty}',
    );
  });

  testWidgets('PROBE C1b: after transition completes, back press works', (
    tester,
  ) async {
    final repo = MemoryRepository();
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.enterText(find.byKey(const Key('entry-content')), '未保存内容');
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    // now on the review tab, back press
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    debugPrint(
      'PROBE C1b after back on review tab composerVisible=${find.byKey(const Key('entry-content')).evaluate().isNotEmpty}',
    );
  });

  testWidgets('PROBE C2: material localizations under zh_CN device locale', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(JournalApp(repository: MemoryRepository()));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(NavigationBar));
    debugPrint(
      'PROBE C2 resolvedLocale=${Localizations.localeOf(ctx)}',
    );
    final ml = MaterialLocalizations.of(ctx);
    debugPrint('PROBE C2 copy=${ml.copyButtonLabel}');
    debugPrint('PROBE C2 paste=${ml.pasteButtonLabel}');
    debugPrint('PROBE C2 selectAll=${ml.selectAllButtonLabel}');
    debugPrint('PROBE C2 backTooltip=${ml.backButtonTooltip}');

    // Push the 本地数据说明 page and read the back button tooltip.
    await tester.tap(find.byKey(const Key('tab-mine')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本地数据说明'));
    await tester.pumpAndSettle();
    final back = tester.widget<BackButton>(find.byType(BackButton));
    debugPrint('PROBE C2 backButtonTooltip=${back.tooltip}');
  });
}
