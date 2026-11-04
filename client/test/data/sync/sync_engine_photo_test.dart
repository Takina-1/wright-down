import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';
import 'package:local_diary/src/data/sync/fake_oss.dart';
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
      final oss = FakeOSS();
      final remote = _FakeRemote();
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        oss: oss,
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
      final oss = FakeOSS();
      // 先上传一份照片到 OSS，拿到 key。
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
        oss: oss,
        now: () => DateTime.now(),
      );
      await engine.pullOnce();
      final all = await repo.exportAll();
      final e = all.singleWhere((x) => x.id == 'e2');
      expect(e.photoKey, key,
          reason: 'pull 后 photoKey 必须等于远端字段携带的 OSS key');
      expect(e.photo, Uint8List.fromList([9, 9, 9]),
          reason: 'pull 后必须从 OSS 下载 BLOB 落本地 photo');
      await repo.close();
      await oss.close();
    });
  });
}
