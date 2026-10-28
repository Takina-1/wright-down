import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'src/data/local/sqlite_entry_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Startup());
}

class _Startup extends StatefulWidget {
  const _Startup();
  @override
  State<_Startup> createState() => _StartupState();
}

class _StartupState extends State<_Startup> {
  late Future<SqliteEntryRepository> _repository = _open();
  Future<SqliteEntryRepository> _open() async => SqliteEntryRepository(
    factory: databaseFactory,
    path: path.join(await getDatabasesPath(), 'local_diary.db'),
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
