import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';
import 'package:local_diary/src/data/sync/fake_cos.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sync_core/sync_core.dart';

class _FakeRemote implements SyncRemote {
  SyncPullResponse? nextPull;
  @override
  Future<SyncPullResponse> pull(String t, int c) async =>
      nextPull ?? SyncPullResponse(cursor: c, entries: []);
  @override
  Future<void> push(String t, SyncPushBatch b) async {}
}

class _FakeAuth implements AuthProvider {
  @override
  Future<AuthResult> register(String e, String p) async =>
      throw UnimplementedError();
  @override
  Future<AuthResult> login(String e, String p) async =>
      AuthResult(userId: 'u1', token: 'tok');
  @override
  Future<AuthResult?> current() async =>
      AuthResult(userId: 'u1', token: 'tok');
  @override
  Future<void> signOut() async {}
}

/// 模拟真机服务端 COS 代理：返回**带前缀**的 key（`photos/<sha256>`），
/// 并统计上传次数——用于 T-33 回归（带前缀的 photoKey 不得导致重复上传）。
class _PrefixedKeyCos implements CosGateway {
  int uploads = 0;
  int downloads = 0;
  final List<Uint8List> uploaded = [];

  @override
  Future<String> upload(Uint8List bytes) async {
    uploads++;
    uploaded.add(bytes);
    return 'photos/${sha256.convert(bytes).toString()}';
  }

  @override
  Future<Uint8List> download(String key) async {
    downloads++;
    return uploaded.isEmpty ? Uint8List(0) : uploaded.first;
  }

  @override
  Future<String> presign(String key) async => 'fake://$key';
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('SyncEngine photo', () {
    test('push 上传本地 photo 设 photoKey', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final oss = FakeCos();
      final remote = _FakeRemote();
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        cos: oss,
        now: () => DateTime.now(),
      );
      await repo.save(Entry(
        id: 'e1',
        content: 'x',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dayKey: '2026-11-03',
        photo: Uint8List.fromList([1, 2, 3]),
      ));
      await engine.pushOnce();
      final all = await repo.exportAll();
      expect(all.single.photoKey, isNotNull,
          reason: 'push 后本地 photo 必须已上传并落 photoKey');
      await repo.close();
      await oss.close();
    });

    test('pull 下载远端 photoKey 的 BLOB', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final oss = FakeCos();
      // 先上传一份照片到 COS，拿到 key。
      final key = await oss.upload(Uint8List.fromList([9, 9, 9]));
      final remote = _FakeRemote();
      remote.nextPull = SyncPullResponse(cursor: 1, entries: [
        SyncEntry(
          id: 'e2',
          createdAt: 1000,
          fields: {
            'photo': FieldValue(key, 5000),
            'content': FieldValue('hi', 100),
          },
        ),
      ]);
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        cos: oss,
        now: () => DateTime.now(),
      );
      await engine.pullOnce();
      final all = await repo.exportAll();
      final e = all.singleWhere((x) => x.id == 'e2');
      expect(e.photoKey, key,
          reason: 'pull 后 photoKey 必须等于远端字段携带的 COS key');
      expect(e.photo, Uint8List.fromList([9, 9, 9]),
          reason: 'pull 后必须从 COS 下载 BLOB 落本地 photo');
      await repo.close();
      await oss.close();
    });

    test('T-12 同条目换照片后 push 重传新照片', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final oss = FakeCos();
      final remote = _FakeRemote();
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        cos: oss,
        now: () => DateTime.now(),
      );
      // 首次：photoA 上传，photoKeyA 落库。
      final photoA = Uint8List.fromList([1, 2, 3]);
      await repo.save(Entry(
        id: 'e1',
        content: 'x',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dayKey: '2026-11-03',
        photo: photoA,
      ));
      await engine.pushOnce();
      final afterFirst = (await repo.exportAll()).single;
      final keyA = afterFirst.photoKey!;
      expect(keyA, sha256.convert(photoA).toString());

      // 换照片：同一条目 photo=photoB，但 photoKey 仍是旧 hash（模拟选新照片）。
      final photoB = Uint8List.fromList([4, 5, 6, 7]);
      await repo.save(Entry(
        id: 'e1',
        content: 'x',
        createdAt: afterFirst.createdAt,
        updatedAt: DateTime.now(),
        dayKey: '2026-11-03',
        photo: photoB,
        photoKey: keyA,
      ));
      await engine.pushOnce();
      final afterSecond = (await repo.exportAll()).single;
      final keyB = afterSecond.photoKey!;
      expect(keyB, sha256.convert(photoB).toString(),
          reason: '换照片后必须重传，photoKey 更新为新照片的 hash');
      expect(keyB, isNot(keyA));
      // 新照片可从 COS 下载（重传成功落库）。
      final downloaded = await oss.download(keyB);
      expect(downloaded, photoB);
      await repo.close();
      await oss.close();
    });

    test('T-12 远端 photoKey 变更时 pull 重下覆盖本地缓存', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final oss = FakeCos();
      final keyA = await oss.upload(Uint8List.fromList([1, 2, 3]));
      final keyB = await oss.upload(Uint8List.fromList([4, 5, 6, 7]));
      final remote = _FakeRemote();
      // 本地已有 photoA + photoKeyA；远端返回 photoKeyB（照片已变更）。
      await repo.save(Entry(
        id: 'e3',
        content: 'x',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dayKey: '2026-11-03',
        photo: Uint8List.fromList([1, 2, 3]),
        photoKey: keyA,
      ));
      remote.nextPull = SyncPullResponse(cursor: 1, entries: [
        SyncEntry(
          id: 'e3',
          createdAt: 1000,
          fields: {
            // t 必须大于本地 photo stamp（2026 年毫秒 ~1.79e12）——取 13 位大值。
            'photo': FieldValue(keyB, 9999999999999),
            'content': FieldValue('x', 100),
          },
        ),
      ]);
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        cos: oss,
        now: () => DateTime.now(),
      );
      await engine.pullOnce();
      final e = (await repo.exportAll()).singleWhere((x) => x.id == 'e3');
      expect(e.photoKey, keyB);
      expect(e.photo, Uint8List.fromList([4, 5, 6, 7]),
          reason: '远端照片变更后必须重下覆盖本地旧 BLOB');
      await repo.close();
      await oss.close();
    });

    test('T-33 带前缀的 photoKey 不触发重复上传', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final cos = _PrefixedKeyCos();
      final remote = _FakeRemote();
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        cos: cos,
        now: () => DateTime.now(),
      );
      final photo = Uint8List.fromList([1, 2, 3]);
      await repo.save(Entry(
        id: 'e1',
        content: '带照片',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dayKey: '2026-11-19',
        photo: photo,
      ));

      await engine.pushOnce();
      final afterFirst = (await repo.exportAll()).single;
      expect(afterFirst.photoKey, 'photos/${sha256.convert(photo).toString()}',
          reason: '服务端返回的是带前缀的 key');
      expect(cos.uploads, 1);

      // 第二次推送：photoKey 带前缀但照片内容未变——不得重传（T-33）。
      await engine.pushOnce();
      expect(cos.uploads, 1,
          reason: 'photoKey 带前缀时也不得重复上传同一张照片（T-33）');
      await repo.close();
    });

    test('T-33 pull 时带前缀的 photoKey 不触发重复下载', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final cos = _PrefixedKeyCos();
      final remote = _FakeRemote();
      final photo = Uint8List.fromList([1, 2, 3]);
      final digest = sha256.convert(photo).toString();
      await repo.save(Entry(
        id: 'e1',
        content: '远端带前缀 photoKey',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dayKey: '2026-11-19',
        photo: photo,
        photoKey: 'photos/$digest',
      ));
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        cos: cos,
        now: () => DateTime.now(),
      );
      remote.nextPull = SyncPullResponse(cursor: 1, entries: [
        SyncEntry(
          id: 'e1',
          createdAt: 1000,
          fields: {
            'photo': FieldValue('photos/$digest', 9999999999999),
            'content': FieldValue('远端带前缀 photoKey', 100),
          },
        ),
      ]);
      await engine.pullOnce();
      final e = (await repo.exportAll()).singleWhere((x) => x.id == 'e1');
      expect(e.photoKey, 'photos/$digest');
      expect(cos.downloads, 0,
          reason: '本地照片与远端 photoKey（带前缀）一致时不得重复下载（T-33）');
      await repo.close();
    });
  });
}
