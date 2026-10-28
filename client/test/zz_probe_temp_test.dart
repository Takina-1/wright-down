import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/app.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// TEMPORARY PROBE - mirrors client/lib/main.dart _Startup exactly, except the
// db path is injected so it can point at an unopenable location.
class ProbeStartup extends StatefulWidget {
  const ProbeStartup({super.key, required this.dbPath});
  final String dbPath;
  @override
  State<ProbeStartup> createState() => _ProbeStartupState();
}

class _ProbeStartupState extends State<ProbeStartup> {
  late Future<SqliteEntryRepository> _repository = _open();
  Future<SqliteEntryRepository> _open() async => SqliteEntryRepository(
    factory: databaseFactoryFfi,
    path: widget.dbPath,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<SqliteEntryRepository>(
    future: _repository,
    builder: (context, snapshot) {
      if (snapshot.hasData) return JournalApp(repository: snapshot.requireData);
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('暂时无法打开本地存储'),
                      TextButton(
                        onPressed: () => setState(() {
                          _repository = _open();
                        }),
                        child: const Text('重试'),
                      ),
                    ],
                  )
                : const Text('正在准备你的记录空间…'),
          ),
        ),
      );
    },
  );
}

void main() {
  sqfliteFfiInit();

  testWidgets('broken db path: startup error screen is never shown', (
    tester,
  ) async {
    final temp = await Directory.systemTemp.createTemp('probe_');
    // A directory can never be opened as a sqlite db file.
    final broken = Directory('${temp.path}/journal.db')
      ..createSync(recursive: true);

    await tester.pumpWidget(ProbeStartup(dbPath: broken.path));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('暂时无法打开本地存储'),
      findsNothing,
      reason: 'startup error screen must not appear',
    );
    expect(find.text('正在准备你的记录空间…'), findsNothing);
    expect(
      find.byKey(const Key('entry-content')),
      findsOneWidget,
      reason: 'the normal composer is rendered instead',
    );

    // The failure only shows up on the first autosave.
    await tester.enterText(find.byKey(const Key('entry-content')), '第一句话');
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text('保存失败，文字仍在此处。请检查存储空间后重试。'),
      findsOneWidget,
    );
    expect(find.text('暂时无法打开本地存储'), findsNothing);

    addTearDown(() => temp.delete(recursive: true));
  });

  test('openDatabase failure only surfaces at save/list time', () async {
    final temp = await Directory.systemTemp.createTemp('probe_');
    final broken = Directory('${temp.path}/journal.db')
      ..createSync(recursive: true);

    // Same shape as main.dart _open(): resolves with a repository object.
    final future = Future<SqliteEntryRepository>.value(
      SqliteEntryRepository(factory: databaseFactoryFfi, path: broken.path),
    );
    final repo = await future;
    expect(repo, isNotNull);

    Object? caught;
    try {
      await repo.list();
    } catch (e) {
      caught = e;
    }
    expect(caught, isNotNull, reason: 'the failure appears only on use');
    addTearDown(() => temp.delete(recursive: true));
  });
}
