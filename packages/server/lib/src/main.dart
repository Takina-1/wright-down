import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

import 'fake_sync_store.dart';
import 'handlers.dart';
import 'server_config.dart';
import 'sync_store.dart';

/// 装配 4 个路由。生产用 PostgresSyncStore；本 Part 用 FakeSyncStore（内存）。
Handler createApp(SyncStore store) {
  final router = Router()
    ..post('/auth/register', registerHandler(store))
    ..post('/auth/login', loginHandler(store))
    ..get('/sync', pullHandler(store))
    ..post('/sync/batch', pushHandler(store));
  return router;
}

/// 启动服务。监听地址与端口由环境变量决定，默认只绑回环。
Future<void> serveDiarySync({Map<String, String>? env, SyncStore? store}) async {
  final cfg = ServerConfig.fromEnv(env ?? Platform.environment);
  final s = store ?? FakeSyncStore();
  await serve(createApp(s), cfg.host, cfg.port);
}
