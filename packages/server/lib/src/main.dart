import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

import 'fake_sync_store.dart';
import 'handlers.dart';
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

Future<void> main(List<String> args) async {
  final store = FakeSyncStore();
  await serve(createApp(store), '0.0.0.0', 8080);
  // 运行入口不做单元测试（无 HTTP 客户端环境），由 dart analyze 保证可编译。
}
