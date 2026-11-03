import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_diary/src/data/remote/email_password_provider.dart';

void main() {
  group('EmailPasswordProvider', () {
    test('login 成功返回 AuthResult 并持久化 token', () async {
      Future<http.Response> handler(http.Request req) async => http.Response(
        jsonEncode({'userId': 'u1', 'token': 'tok'}), 200,
        headers: {'content-type': 'application/json'});
      final store = _FakeTokenStore();
      final p = EmailPasswordProvider(http.Client(), 'http://x', store, handler: handler);
      final r = await p.login('a@b.com', 'pw');
      expect(r.token, 'tok');
      expect(store.value, 'tok');
    });

    test('current 从 store 读取', () async {
      final store = _FakeTokenStore(value: 'tok');
      Future<http.Response> handler(http.Request req) async => http.Response('', 200);
      final p = EmailPasswordProvider(http.Client(), 'http://x', store, handler: handler);
      expect((await p.current())?.token, 'tok');
    });
  });
}

class _FakeTokenStore implements TokenStore {
  String? value;
  _FakeTokenStore({this.value});
  @override Future<String?> read() async => value;
  @override Future<void> write(String? t) async { value = t; }
}
