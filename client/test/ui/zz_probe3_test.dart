import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/app.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('PROBE C2b: rendered tooltip + delegate defaults', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(JournalApp(repository: MemoryRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-mine')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本地数据说明'));
    await tester.pumpAndSettle();
    debugPrint(
      'PROBE C2b findsTooltipBack=${find.byTooltip('Back').evaluate().length}',
    );
    debugPrint(
      'PROBE C2b findsTooltip返回=${find.byTooltip('返回').evaluate().length}',
    );
    final ctx = tester.element(find.byType(BackButton));
    debugPrint(
      'PROBE C2b resolvedLocale=${Localizations.localeOf(ctx)}',
    );
    debugPrint(
      'PROBE C2b localizations=${Localizations.of(ctx, MaterialLocalizations).runtimeType}',
    );
    // Show the rendered context menu labels for the entry field.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-write')));
    await tester.pumpAndSettle();
    final ctx2 = tester.element(find.byKey(const Key('entry-content')));
    debugPrint(
      'PROBE C2b localeInComposer=${Localizations.localeOf(ctx2)}',
    );
  });
}
