import 'package:test/test.dart';
import 'package:server/server.dart';

void main() {
  group('FakeSyncStore 鉴权', () {
    test('注册后能登录', () async {
      final store = FakeSyncStore();
      final r = await store.register('a@b.com', 'pw');
      expect(r.userId.isNotEmpty, isTrue);
      expect(r.token.isNotEmpty, isTrue);
      final back = await store.login('a@b.com', 'pw');
      expect(back?.userId, r.userId);
    });

    test('错误密码登录失败', () async {
      final store = FakeSyncStore();
      await store.register('a@b.com', 'pw');
      expect(await store.login('a@b.com', 'wrong'), isNull);
    });

    test('不存在的邮箱登录返回 null（时序防护）', () async {
      final store = FakeSyncStore();
      // 邮箱不存在时 login 仍跑一次 bcrypt 再返回 null，
      // 使响应耗时与"密码错误"不可区分，防止用响应时间枚举已注册邮箱。
      expect(await store.login('nobody@b.com', 'pw'), isNull);
    });

    test('重复邮箱注册失败', () async {
      final store = FakeSyncStore();
      await store.register('a@b.com', 'pw');
      expect(
        () => store.register('a@b.com', 'pw2'),
        throwsStateError,
      );
    });

    test('token 能解析回 userId', () async {
      final store = FakeSyncStore();
      final r = await store.register('a@b.com', 'pw');
      expect(await store.userIdForToken(r.token), r.userId);
      expect(await store.userIdForToken('bad'), isNull);
    });
  });
}
