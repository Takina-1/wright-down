import 'package:server/server.dart';
import 'package:test/test.dart';

void main() {
  group('ServerConfig.fromEnv', () {
    test('缺省时绑定回环地址与 8080', () {
      final c = ServerConfig.fromEnv(const {});
      expect(c.host, '127.0.0.1');
      expect(c.port, 8080);
    });

    test('PORT 可覆盖', () {
      expect(ServerConfig.fromEnv(const {'PORT': '9090'}).port, 9090);
    });

    test('PORT 非法时回落默认端口', () {
      expect(ServerConfig.fromEnv(const {'PORT': 'abc'}).port, 8080);
      expect(ServerConfig.fromEnv(const {'PORT': ''}).port, 8080);
    });

    test('HOST 可覆盖', () {
      expect(ServerConfig.fromEnv(const {'HOST': '0.0.0.0'}).host, '0.0.0.0');
    });
  });
}
