import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sync_core/sync_core.dart';

import 'app.dart';
import 'src/config/sync_config.dart';
import 'src/data/local/sqlite_entry_repository.dart';
import 'src/data/remote/email_password_provider.dart';
import 'src/data/remote/remote_repo.dart';
import 'src/data/sync/fake_cos.dart';
import 'src/data/sync/sync_engine.dart';

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
  late Future<SyncEngine> _engine = _open();
  Future<SyncEngine> _open() async {
    final repository = SqliteEntryRepository(
      factory: databaseFactory,
      path: path.join(await getDatabasesPath(), 'local_diary.db'),
    );
    final httpClient = http.Client();
    final baseUrl = syncBaseUrl();
    final auth = EmailPasswordProvider(
      httpClient,
      baseUrl,
      InMemoryTokenStore(),
    );
    final engine = SyncEngine(
      repository: repository,
      remote: RemoteRepo(httpClient, baseUrl, const SyncCodec()),
      auth: auth,
      // FakeCos 是开发期占位实现（本地临时目录）；真机 COS 网关待后续
      // Part 接入后替换。
      cos: FakeCos(),
      now: DateTime.now,
    );
    // 启动即拉一次 + 开启 5 分钟周期拉取。未登录时 triggerPull 内部
    // _me() 返回 null 提前退出，不会发网络请求。
    engine.start();
    return engine;
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<SyncEngine>(
    future: _engine,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        final engine = snapshot.requireData;
        return JournalApp(
          repository: engine.repository,
          syncEngine: engine,
        );
      }
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
                          _engine = _open();
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
