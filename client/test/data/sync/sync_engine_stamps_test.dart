import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';
import 'package:local_diary/src/data/sync/fake_cos.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/sync/entry_sync_map.dart';
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

  test('pull 后 saveMerged 保留远端字段时间戳', () async {
    final repo =
        SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
    final remote = _FakeRemote();
    // 远端 content t=5000
    remote.nextPull = SyncPullResponse(cursor: 1, entries: [
      SyncEntry(
          id: 'e2',
          createdAt: 1000,
          fields: const {'content': FieldValue('remote', 5000)}),
    ]);
    final engine = SyncEngine(
      repository: repo,
      remote: remote,
      auth: _FakeAuth(),
      cos: FakeCos(),
      now: () => DateTime.now(),
    );
    await engine.pullOnce();
    final all = await repo.exportAll();
    final e = all.singleWhere((x) => x.id == 'e2');
    // 关键：syncStamps['content'] == 5000（远端 t），不是 updatedAt
    expect(e.syncStamps['content'], 5000);
    expect(e.content, 'remote');
    await repo.close();
  });
}
