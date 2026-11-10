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

    test('T-07 refresh 换新 token', () async {
      Future<http.Response> handler(http.Request req) async => http.Response(
        jsonEncode({'userId': 'u1', 'token': 'new', 'refreshToken': 'rt2'}), 200,
        headers: {'content-type': 'application/json'});
      final repo = RemoteRepo(http.Client(), 'http://x', const SyncCodec(), handler: handler);
      final r = await repo.refresh('rt');
      expect(r.token, 'new');
      expect(r.refreshToken, 'rt2');
    });

    test('T-07 pull 401 → tokenRefresher 重试一次成功', () async {
      var calls = 0;
      Future<http.Response> handler(http.Request req) async {
        calls++;
        if (calls == 1) return http.Response('invalid token', 401);
        return http.Response(
          jsonEncode({'cursor': 0, 'entries': []}), 200,
          headers: {'content-type': 'application/json'});
      }
      var refreshed = false;
      final repo = RemoteRepo(http.Client(), 'http://x', const SyncCodec(),
        handler: handler,
        tokenRefresher: () async {
          refreshed = true;
          return 'new-tok';
        });
      final r = await repo.pull('old-tok', 0);
      expect(r.cursor, 0);
      expect(refreshed, isTrue);
      expect(calls, 2);
    });

    test('T-07 pull 401 → refresh 后仍 401 抛 StateError', () async {
      Future<http.Response> handler(http.Request req) async =>
          http.Response('invalid token', 401);
      final repo = RemoteRepo(http.Client(), 'http://x', const SyncCodec(),
        handler: handler,
        tokenRefresher: () async => 'new-tok');
      await expectLater(repo.pull('old-tok', 0), throwsA(isA<StateError>()));
    });
  });
}
