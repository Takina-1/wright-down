import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_diary/src/data/remote/tls_trust.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 偏差：Flutter 3.47.x 的 TestWidgetsFlutterBinding.overrideHttpClient 默认为 true，
  // initInstances() 会安装 _MockHttpOverrides（见 flutter_test/_binding_io.dart），
  // 把所有 HttpClient 替换为返回 400 的假实现，从而阻断真实 TLS 握手 —— 这会让本测试
  // 的「untrusted→HandshakeException / trusted→200 pong」永远无法成立。
  // 这里恢复真实 dart:io.HttpClient，使测试真正连上本地 TLS 服务器（仅本文件进程生效）。
  HttpOverrides.global = null;

  const fixtureDir = 'test/fixtures/tls';

  Future<HttpServer> _startTlsServer() async {
    final ctx = SecurityContext()
      ..useCertificateChain('$fixtureDir/test_server.crt')
      ..usePrivateKey('$fixtureDir/test_server.key');
    final server = await HttpServer.bindSecure('127.0.0.1', 0, ctx);
    server.listen((req) async {
      req.response.write('pong');
      await req.response.close();
    });
    return server;
  }

  group('TlsTrust', () {
    test('asset 可加载，且是 PEM 格式的 CA 证书', () async {
      final data = await rootBundle.load('assets/diary_ca.crt');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      expect(bytes.length, greaterThan(100));
      final pem = String.fromCharCodes(bytes);
      expect(pem, startsWith('-----BEGIN CERTIFICATE-----'));
      expect(pem, contains('-----END CERTIFICATE-----'));
    });

    test('asset 与 res/raw 内嵌的那份字节一致（防止 CA 漂移）', () async {
      final data = await rootBundle.load('assets/diary_ca.crt');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final onDisk =
          await File('android/app/src/main/res/raw/diary_ca.crt').readAsBytes();
      expect(bytes, equals(onDisk));
    });

    test('追加信任锚点后，能连上自签证书的本地 TLS 服务器', () async {
      final server = await _startTlsServer();
      addTearDown(() => server.close(force: true));

      final untrusted = http.Client();
      addTearDown(untrusted.close);
      await expectLater(
        untrusted.get(Uri.parse('https://localhost:${server.port}/')),
        throwsA(isA<HandshakeException>()),
      );

      final ca = await File('$fixtureDir/test_ca.crt').readAsBytes();
      final trusted =
          await TlsTrust.instance.clientWithTrustedCerts([ca]);
      addTearDown(trusted.close);
      final r =
          await trusted.get(Uri.parse('https://localhost:${server.port}/'));
      expect(r.statusCode, 200);
      expect(r.body, 'pong');
    });
  });
}
