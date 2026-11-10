import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

import 'cos_proxy.dart';
import 'fake_sync_store.dart';
import 'handlers.dart';
import 'pg_config.dart';
import 'postgres_sync_store.dart';
import 'server_config.dart';
import 'sync_store.dart';

/// 装配同步路由；凭证齐全时加挂照片代理路由（T-24）。
/// COS 凭证经环境变量注入（COS_BUCKET/COS_SECRET_ID/COS_SECRET_KEY），
/// 缺失时只挂同步路由（开发/无对象存储模式）。
/// [gateway] 仅测试注入用；生产从凭证构造真实 HttpCosStore。
Handler createApp(SyncStore store,
    {CosCredentials? cos, PhotoGateway? gateway}) {
  final router = Router()
    ..post('/auth/register', registerHandler(store))
    ..post('/auth/login', loginHandler(store))
    ..get('/sync', pullHandler(store))
    ..post('/sync/batch', pushHandler(store));

  if (cos != null) {
    final g = gateway ?? PhotoGateway(prefix: cos.prefix, cos: HttpCosStore(cos));
    router
      ..post('/sync/photo/upload', photoUploadHandler(store, g))
      // shelf_router 通配路由用正则参数 /<any|.*>（不是 <...>）。
      ..get('/sync/photo/<any|.*>', photoDownloadHandler(store, g))
      ..head('/sync/photo/<any|.*>', photoExistsHandler(store, g));
  }
  return router;
}

/// 启动服务。监听地址与端口由环境变量决定，默认只绑回环。
/// 存储装配：PG_* 凭证齐全 → PostgresSyncStore（真实落库）；缺任一 →
/// FakeSyncStore 回退（开发/无库模式，重启丢数据）。
Future<void> serveDiarySync(
    {Map<String, String>? env, SyncStore? store}) async {
  final e = env ?? Platform.environment;
  final cfg = ServerConfig.fromEnv(e);
  SyncStore s;
  if (store != null) {
    s = store;
  } else {
    final pg = PgConfig.fromEnv(e);
    if (pg != null) {
      s = await PostgresSyncStore.connect(pg);
    } else {
      print('[warn] PG 凭证缺失，回退 FakeSyncStore（重启后数据不持久化）');
      s = FakeSyncStore();
    }
  }
  final cos = CosCredentials.fromEnv(e);
  if (cos == null) {
    print('[warn] 未检测到 COS_* 环境变量，跳过照片代理路由');
  }
  await serve(createApp(s, cos: cos), cfg.host, cfg.port);
}
