import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_diary/src/data/remote/remote_repo.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  group('RemoteRepo', () {
    test('pull 解析 cursor 与 entries', () async {
      Future<http.Response> handler(http.Request req) async {
        expect(req.url.toString(), endsWith('/sync?cursor=0'));
        return http.Response(
          jsonEncode({'cursor': 7, 'entries': []}), 200,
          headers: {'content-type': 'application/json'});
      }
      final repo = RemoteRepo(http.Client(), 'http://x', const SyncCodec(), handler: handler);
      final r = await repo.pull('tok', 0);
      expect(r.cursor, 7);
    });

    test('push 发送批次', () async {
      var pushed = false;
      Future<http.Response> handler(http.Request req) async {
        pushed = true;
        expect(req.method, 'POST');
        return http.Response('{"ok":true}', 200, headers: {'content-type': 'application/json'});
      }
      final repo = RemoteRepo(http.Client(), 'http://x', const SyncCodec(), handler: handler);
      await repo.push('tok', SyncPushBatch(patches: []));
      expect(pushed, isTrue);
    });

    test('register 返回 token', () async {
      Future<http.Response> handler(http.Request req) async => http.Response(
        jsonEncode({'userId': 'u1', 'token': 'tok'}), 200,
        headers: {'content-type': 'application/json'});
      final repo = RemoteRepo(http.Client(), 'http://x', const SyncCodec(), handler: handler);
      final r = await repo.register('a@b.com', 'pw');
      expect(r.token, 'tok');
    });
  });
}
