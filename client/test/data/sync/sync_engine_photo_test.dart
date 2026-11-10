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
  });
}
