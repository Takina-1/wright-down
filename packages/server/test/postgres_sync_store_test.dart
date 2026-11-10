import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:server/server.dart';
import 'package:sync_core/sync_core.dart';
import 'package:test/test.dart';

/// PostgreSQL 集成测试。
///
/// 运行条件：PG_HOST + PG_PASSWORD 环境变量齐全（ECS 部署时由 pg.env 提供）。
/// 缺省时全部跳过——本机无 PG 不阻塞 `dart test` 绿灯。
///
/// 断言语义基准 = FakeSyncStore（fake_sync_store_sync_test.dart /
/// fake_sync_store_auth_test.dart 同款断言）。

String? _skipReason() {
  final e = Platform.environment;
  if ((e['PG_HOST'] ?? '').isNotEmpty &&
      (e['PG_PASSWORD'] ?? '').isNotEmpty) {
    return null;
  }
  return '未配置 PG_*（PG_HOST/PG_PASSWORD），跳过集成测试';
}

void main() {
  final skip = _skipReason();

  group('PostgresSyncStore · 语义与 FakeSyncStore 等价', () {
    test('注册/登录/token/鉴权', skip: skip, () async {
      final store = await PostgresSyncStore.connect(
        PgConfig.fromEnv(Platform.environment)!,
      );
      try {
        final email =
            'pg-acc-${DateTime.now().millisecondsSinceEpoch}@local.test';
        final r1 = await store.register(email, 'pw-123');
        expect(r1.userId, startsWith('u'));
        expect(r1.token, hasLength(48));

        // 重复邮箱 → StateError（handler 409）
        await expectLater(
            store.register(email, 'pw'), throwsA(isA<StateError>()));

        // 超长口令 → ArgumentError（handler 400）
        await expectLater(
            store.register('$email.x', 'a' * 73),
            throwsA(isA<ArgumentError>()));

        // 登录：错误密码 null（401）；不存在邮箱也跑 bcrypt 后 null（401）
        expect(await store.login(email, 'wrong'), isNull);
        expect(await store.login('nobody@local.test', 'pw'), isNull);

        final r2 = await store.login(email, 'pw-123');
        expect(r2, isNotNull);
        expect(r2!.userId, r1.userId);

        // token 映射
        expect(await store.userIdForToken(r2.token), r1.userId);
        expect(await store.userIdForToken('bogus'), isNull);
      } finally {
        await store.close();
      }
    });

    test('push/pull：条目入库、游标推进、空批 cursor 不变', skip: skip,
        () async {
      final store = await PostgresSyncStore.connect(
        PgConfig.fromEnv(Platform.environment)!,
      );
      try {
        final email =
            'pg-acc-${DateTime.now().millisecondsSinceEpoch}@local.test';
        final uid = (await store.register(email, 'pw')).userId;
        final createdAt = 1733886800000; // 2025-02-09 前后毫秒

        await store.push(uid, SyncPushBatch(patches: [
          EntryPatch(
              id: 'e-1',
              createdAt: createdAt,
              fields: {'content': FieldValue('hello', createdAt)}),
        ]));

        final pull1 = await store.pull(uid, 0);
        expect(pull1.entries, hasLength(1));
        expect(pull1.entries.single.id, 'e-1');
        expect(pull1.entries.single.createdAt, createdAt);
        expect(pull1.entries.single.fields['content']!.v, 'hello');
        expect(pull1.cursor > 0, isTrue);

        // 空批：cursor 不变
        final pull2 = await store.pull(uid, pull1.cursor);
        expect(pull2.entries, isEmpty);
        expect(pull2.cursor, pull1.cursor);

        // 再推一条 → 只返回新条目
        await store.push(uid, SyncPushBatch(patches: [
          EntryPatch(
              id: 'e-2',
              createdAt: createdAt + 1000,
              fields: {'content': FieldValue('second', createdAt + 1000)}),
        ]));
        final pull3 = await store.pull(uid, pull1.cursor);
        expect(pull3.entries.single.id, 'e-2');
        expect(pull3.cursor, greaterThan(pull1.cursor));
      } finally {
        await store.close();
      }
    });

    test('字段级 LWW 与 created_at 冻结', skip: skip, () async {
      final store = await PostgresSyncStore.connect(
        PgConfig.fromEnv(Platform.environment)!,
      );
      try {
        final email =
            'pg-acc-${DateTime.now().millisecondsSinceEpoch}@local.test';
        final uid = (await store.register(email, 'pw')).userId;

        // 首次 push：created_at = 1000，content t=100、mood t=100
        await store.push(uid, SyncPushBatch(patches: [
          EntryPatch(
              id: 'e-1',
              createdAt: 1000,
              fields: {
                'content': FieldValue('old', 100),
                'mood': FieldValue('calm', 100),
              }),
        ]));
        final p1 = await store.pull(uid, 0);
        expect(p1.entries.single.createdAt, 1000);

        // 再 push：content t=50（更旧）应保留 'old'；mood t=300 覆盖
        await store.push(uid, SyncPushBatch(patches: [
          EntryPatch(
              id: 'e-1',
              createdAt: 9999999999,
              fields: {
                'content': FieldValue('older', 50),
                'mood': FieldValue('excited', 300),
              }),
        ]));
        final p2 = await store.pull(uid, p1.cursor);
        final e = p2.entries.single;
        expect(e.createdAt, 1000); // 冻结
        expect(e.fields['content']!.v, 'old'); // t=50 < 100 → 旧值保留
        expect(e.fields['mood']!.v, 'excited'); // t=300 > 100 → 新值

        // 相等 t → incoming 赢
        await store.push(uid, SyncPushBatch(patches: [
          EntryPatch(
              id: 'e-1',
              createdAt: 1000,
              fields: {'content': FieldValue('tie', 100)}),
        ]));
        final p3 = await store.pull(uid, p2.cursor);
        expect(p3.entries.single.fields['content']!.v, 'tie');
      } finally {
        await store.close();
      }
    });

    test('跨用户同 id 隔离 + payload 往返类型', skip: skip, () async {
      final store = await PostgresSyncStore.connect(
        PgConfig.fromEnv(Platform.environment)!,
      );
      try {
        final t = DateTime.now().millisecondsSinceEpoch;
        final a =
            (await store.register('pg-acc-a-$t@local.test', 'pw')).userId;
        final b =
            (await store.register('pg-acc-b-$t@local.test', 'pw')).userId;

        await store.push(a, SyncPushBatch(patches: [
          EntryPatch(
              id: 'shared',
              createdAt: t,
              fields: {
                'content': FieldValue('from-A', t),
                'tags': FieldValue(['a', 'b'], t),
                'photo': FieldValue(null, t),
              }),
        ]));
        await store.push(b, SyncPushBatch(patches: [
          EntryPatch(
              id: 'shared',
              createdAt: t,
              fields: {'content': FieldValue('from-B', t)}),
        ]));

        final pa = await store.pull(a, 0);
        final pb = await store.pull(b, 0);
        expect(pa.entries.single.fields['content']!.v, 'from-A');
        expect(pb.entries.single.fields['content']!.v, 'from-B');
        // payload 往返：List/null 原样
        expect(pa.entries.single.fields['tags']!.v, ['a', 'b']);
        expect(pa.entries.single.fields['photo']!.v, isNull);
      } finally {
        await store.close();
      }
    });

    test('并发 push 不丢条目：seq 串行化（AC-07）', skip: skip, () async {
      final store = await PostgresSyncStore.connect(
        PgConfig.fromEnv(Platform.environment)!,
      );
      try {
        final t = DateTime.now().millisecondsSinceEpoch;
        final u1 =
            (await store.register('pg-acc-1-$t@local.test', 'pw')).userId;
        final u2 =
            (await store.register('pg-acc-2-$t@local.test', 'pw')).userId;

        // 两个用户并发各推 2 条。
        await Future.wait([
          Future.wait([
            store.push(u1, SyncPushBatch(patches: [EntryPatch(
                id: 'c1',
                createdAt: t,
                fields: {'content': FieldValue('c1', t)})] )),
            store.push(u1, SyncPushBatch(patches: [EntryPatch(
                id: 'c2',
                createdAt: t + 1,
                fields: {'content': FieldValue('c2', t + 1)})] )),
          ]),
          Future.wait([
            store.push(u2, SyncPushBatch(patches: [EntryPatch(
                id: 'c1',
                createdAt: t,
                fields: {'content': FieldValue('b1', t)})] )),
            store.push(u2, SyncPushBatch(patches: [EntryPatch(
                id: 'c2',
                createdAt: t + 1,
                fields: {'content': FieldValue('b2', t + 1)})] )),
          ]),
        ]);

        // 不丢：每个用户都拿回自己的两条。
        final p1 = await store.pull(u1, 0);
        final p2 = await store.pull(u2, 0);
        expect(p1.entries, hasLength(2));
        expect(p2.entries, hasLength(2));
        expect(p1.entries.map((e) => e.id).toSet(), {'c1', 'c2'});
        expect(p2.entries.map((e) => e.id).toSet(), {'c1', 'c2'});

        // cursor 各自推进到 max seq；再次拉取为空（不重发）。
        expect(p1.cursor > 0, isTrue);
        expect(await store.pull(u1, p1.cursor).then((r) => r.entries), isEmpty);
        expect(await store.pull(u2, p2.cursor).then((r) => r.entries), isEmpty);
      } finally {
        await store.close();
      }
    });

    test('T-07 register/login 返回 refreshToken', skip: skip, () async {
      final store = await PostgresSyncStore.connect(
        PgConfig.fromEnv(Platform.environment)!,
      );
      try {
        final email =
            'pg-refresh-${DateTime.now().millisecondsSinceEpoch}@local.test';
        final r = await store.register(email, 'pw');
        expect(r.refreshToken, isNotNull);
        expect(r.refreshToken, isNotEmpty);
        final r2 = await store.login(email, 'pw');
        expect(r2!.refreshToken, isNotNull);
        expect(r2.refreshToken, isNotEmpty);
      } finally {
        await store.close();
      }
    });

    test('T-07 refresh 轮换：旧 refresh 作废，新 token 有效', skip: skip,
        () async {
      final store = await PostgresSyncStore.connect(
        PgConfig.fromEnv(Platform.environment)!,
      );
      try {
        final email =
            'pg-refresh-${DateTime.now().millisecondsSinceEpoch}@local.test';
        final r = await store.register(email, 'pw');
        final oldRefresh = r.refreshToken!;
        final r2 = await store.refresh(oldRefresh);
        expect(r2.token, isNot(r.token));
        expect(r2.refreshToken, isNot(oldRefresh));
        // 旧 refresh 作废
        await expectLater(
            store.refresh(oldRefresh), throwsA(isA<StateError>()));
        // 新 refresh 有效
        final r3 = await store.refresh(r2.refreshToken!);
        expect(r3.token, isNotEmpty);
      } finally {
        await store.close();
      }
    });

    test('T-07 access token 过期 → userIdForToken null', skip: skip, () async {
      final config = PgConfig.fromEnv(Platform.environment)!;
      final store = await PostgresSyncStore.connect(config);
      try {
        final email =
            'pg-expire-${DateTime.now().millisecondsSinceEpoch}@local.test';
        final r = await store.register(email, 'pw');
        // 用独立连接把 access token 的 expires_at 设为过去（模拟过期）。
        final conn = await Connection.open(
          Endpoint(
            host: config.host,
            port: config.port,
            database: config.db,
            username: config.user,
            password: config.password,
          ),
          settings: ConnectionSettings(sslMode: SslMode.disable),
        );
        await conn.execute(
          'UPDATE tokens SET expires_at = now() - interval \'1 day\' '
          'WHERE token = \$1',
          parameters: [r.token],
        );
        await conn.close();
        // 过期 token 视为失效
        expect(await store.userIdForToken(r.token), isNull);
      } finally {
        await store.close();
      }
    });
  });
}
