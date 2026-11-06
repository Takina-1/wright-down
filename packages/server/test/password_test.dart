import 'package:server/server.dart';
import 'package:test/test.dart';

void main() {
  group('hashPassword', () {
    test('产出 bcrypt 格式串并内嵌 salt', () {
      final h = hashPassword('correct horse');
      expect(h, startsWith(r'$2b$10$'));
      expect(h.length, 60);
    });

    test('同一密码两次哈希不同（salt 随机）', () {
      expect(hashPassword('same'), isNot(hashPassword('same')));
    });

    test('超过 72 字节抛 ArgumentError（不静默截断）', () {
      expect(() => hashPassword('a' * 73), throwsArgumentError);
    });
  });

  group('verifyPassword', () {
    test('正确密码通过', () {
      expect(verifyPassword('correct horse', hashPassword('correct horse')), isTrue);
    });

    test('错误密码不通过', () {
      expect(verifyPassword('wrong', hashPassword('correct horse')), isFalse);
    });

    test('哈希格式非法返回 false 而非抛异常', () {
      expect(verifyPassword('x', 'not-a-hash'), isFalse);
    });
  });

  group('newToken', () {
    test('返回 48 位十六进制随机串且互不相同', () {
      final t = newToken();
      expect(t.length, 48);
      expect(RegExp(r'^[0-9a-f]{48}$').hasMatch(t), isTrue);
      expect(newToken(), isNot(t));
    });
  });
}
