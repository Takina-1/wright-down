import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_diary/src/data/remote/email_password_provider.dart';

void main() {
  group('EmailPasswordProvider', () {
    test('login 成功返回 AuthResult 并持久化 AuthSession', () async {
      Future<http.Response> handler(http.Request req) async => http.Response(
        jsonEncode({'userId': 'u1', 'token': 'tok', 'refreshToken': 'rt'}), 200,
        headers: {'content-type': 'application/json'});
      final store = _FakeTokenStore();
      final p = EmailPasswordProvider(http.Client(), 'http://x', store, handler: handler);
      final r = await p.login('a@b.com', 'pw');
      expect(r.token, 'tok');
      expect(r.refreshToken, 'rt');
      expect(store.session?.accessToken, 'tok');
      expect(store.session?.refreshToken, 'rt');
    });

    test('current 从 store 读取 access token', () async {
      final store = _FakeTokenStore(session: AuthSession(
          accessToken: 'tok', refreshToken: 'rt', expiresAt: DateTime(2026, 11, 10)));
      Future<http.Response> handler(http.Request req) async => http.Response('', 200);
      final p = EmailPasswordProvider(http.Client(), 'http://x', store, handler: handler);
      expect((await p.current())?.token, 'tok');
    });

    test('T-07 refresh 换新 token 并持久化', () async {
      final store = _FakeTokenStore(session: AuthSession(
          accessToken: 'old', refreshToken: 'rt', expiresAt: DateTime(2026, 11, 10)));
      var refreshCalls = 0;
      Future<http.Response> handler(http.Request req) async {
        if (req.url.path == '/auth/refresh') {
          refreshCalls++;
          return http.Response(
            jsonEncode({'userId': 'u1', 'token': 'new', 'refreshToken': 'rt2'}),
            200,
            headers: {'content-type': 'application/json'});
        }
        return http.Response('', 200);
      }
      final p = EmailPasswordProvider(http.Client(), 'http://x', store, handler: handler);
      final r = await p.refresh();
      expect(r.token, 'new');
      expect(r.refreshToken, 'rt2');
      expect(refreshCalls, 1);
      expect(store.session?.accessToken, 'new');
      expect(store.session?.refreshToken, 'rt2');
    });

    test('T-07 refresh 端点 401 抛错', () async {
      final store = _FakeTokenStore(session: AuthSession(
          accessToken: 'old', refreshToken: 'rt', expiresAt: DateTime(2026, 11, 10)));
      Future<http.Response> handler(http.Request req) async =>
          http.Response('invalid refresh token', 401);
      final p = EmailPasswordProvider(http.Client(), 'http://x', store, handler: handler);
      await expectLater(p.refresh(), throwsA(isA<StateError>()));
    });

    test('T-08 signOut 清空会话', () async {
      final store = _FakeTokenStore(session: AuthSession(
          accessToken: 'tok', refreshToken: 'rt', expiresAt: DateTime(2026, 11, 10)));
      Future<http.Response> handler(http.Request req) async => http.Response('', 200);
      final p = EmailPasswordProvider(http.Client(), 'http://x', store, handler: handler);
      await p.signOut();
      expect(store.session, isNull);
    });
  });
}

class _FakeTokenStore implements TokenStore {
  AuthSession? session;
  _FakeTokenStore({this.session});
  @override Future<AuthSession?> read() async => session;
  @override Future<void> write(AuthSession? s) async { session = s; }
}
