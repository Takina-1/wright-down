import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:server/server.dart';
import 'package:sync_core/sync_core.dart';

Request _req(
  String method,
  String path, {
  Map<String, String> headers = const {},
  String body = '',
}) =>
    Request(method, Uri.parse('http://localhost$path'), headers: headers, body: body);

Future<Map<String, dynamic>> _body(Response r) async =>
    jsonDecode(await r.readAsString()) as Map<String, dynamic>;

void main() {
  group('handlers', () {
    test('register 返回 userId 与 token', () async {
      final store = FakeSyncStore();
      final h = registerHandler(store);
      final r = await h(_req('POST', '/auth/register',
          body: '{"email":"a@b.com","password":"pw"}'));
      expect(r.statusCode, 200);
      final j = await _body(r);
      expect(j['userId'], isA<String>());
      expect(j['token'], isA<String>());
    });

    test('login 错误密码返回 401', () async {
      final store = FakeSyncStore();
      await store.register('a@b.com', 'pw');
      final h = loginHandler(store);
      final r = await h(_req('POST', '/auth/login',
          body: '{"email":"a@b.com","password":"wrong"}'));
      expect(r.statusCode, 401);
    });

    test('register 超长密码返回 400', () async {
      final store = FakeSyncStore();
      final h = registerHandler(store);
      final r = await h(_req('POST', '/auth/register',
          body: '{"email":"a@b.com","password":"${'a' * 73}"}'));
      expect(r.statusCode, 400);
    });

    test('login 超长密码返回 400', () async {
      final store = FakeSyncStore();
      final h = loginHandler(store);
      // 邮箱不存在时 login 内 hashPassword 直接抛 ArgumentError，
      // handler 捕获后返回 400。
      final r = await h(_req('POST', '/auth/login',
          body: '{"email":"nobody@b.com","password":"${'a' * 73}"}'));
      expect(r.statusCode, 400);
    });

    test('login 已注册邮箱超长密码返回 400', () async {
      final store = FakeSyncStore();
      await store.register('a@b.com', 'pw');
      final h = loginHandler(store);
      // 已注册邮箱 + 超长密码：login 的 pre-check 抛 ArgumentError，
      // handler 捕获后返回 400，与未注册邮箱路径一致。
      final r = await h(_req('POST', '/auth/login',
          body: '{"email":"a@b.com","password":"${'a' * 73}"}'));
      expect(r.statusCode, 400);
    });

    test('pull 需要鉴权：无 token 返回 401', () async {
      final store = FakeSyncStore();
      final h = pullHandler(store);
      final r = await h(_req('GET', '/sync?cursor=0'));
      expect(r.statusCode, 401);
    });

    test('pull 带 token 返回同步结果', () async {
      final store = FakeSyncStore();
      final reg = await store.register('a@b.com', 'pw');
      await store.push(reg.userId, SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 1, fields: const {
          'content': FieldValue('hi', 100),
        }),
      ]));
      final h = pullHandler(store);
      final r = await h(_req('GET', '/sync?cursor=0',
          headers: {'authorization': 'Bearer ${reg.token}'}));
      expect(r.statusCode, 200);
      final j = await _body(r);
      expect(j['cursor'], isA<int>());
      expect((j['entries'] as List), hasLength(1));
    });

    test('push 带 token 写入后可 pull', () async {
      final store = FakeSyncStore();
      final reg = await store.register('a@b.com', 'pw');
      final h = pushHandler(store);
      final r = await h(_req('POST', '/sync/batch',
          headers: {'authorization': 'Bearer ${reg.token}'},
          body: '{"patches":[]}'));
      expect(r.statusCode, 200);
      final pulled = await store.pull(reg.userId, 0);
      expect(pulled.entries, isEmpty);
    });
  });
}
