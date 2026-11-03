import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  group('AuthProvider 契约', () {
    test('测试替身可实现 AuthProvider', () async {
      final p = _FakeAuth();
      final r = await p.login('a@b.com', 'pw');
      expect(r.userId, 'u1');
      expect(r.token, 'tok');
      expect(await p.current(), isNull);
      await p.signOut();
    });
  });

  group('OSSGateway 契约', () {
    test('测试替身可实现 OSSGateway', () async {
      final g = _FakeOss();
      final key = await g.upload(Uint8List.fromList([1, 2, 3]));
      expect(key, 'key-1');
      expect((await g.download('key-1')), Uint8List.fromList([1, 2, 3]));
      expect(await g.presign('key-1'), 'fake://key-1');
    });
  });
}

class _FakeAuth implements AuthProvider {
  @override
  Future<AuthResult> register(String email, String password) async =>
      AuthResult(userId: 'u1', token: 'tok');
  @override
  Future<AuthResult> login(String email, String password) async =>
      AuthResult(userId: 'u1', token: 'tok');
  @override
  Future<AuthResult?> current() async => null;
  @override
  Future<void> signOut() async {}
}

class _FakeOss implements OSSGateway {
  @override
  Future<String> upload(Uint8List bytes) async => 'key-1';
  @override
  Future<Uint8List> download(String key) async =>
      Uint8List.fromList([1, 2, 3]);
  @override
  Future<String> presign(String key) async => 'fake://$key';
}
