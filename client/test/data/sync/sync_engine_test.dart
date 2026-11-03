import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sync_core/sync_core.dart';

class _FakeRemote implements SyncRemote {
  SyncPullResponse? nextPull;
  final List<SyncPushBatch> pushes = [];
  @override
  Future<SyncPullResponse> pull(String t, int c) async =>
      nextPull ?? SyncPullResponse(cursor: c, entries: []);
  @override
  Future<void> push(String t, SyncPushBatch b) async {
    pushes.add(b);
  }
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

  group('SyncEngine', () {
    test('push：脏条目推给 RemoteRepo', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final remote = _FakeRemote();
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        now: () => DateTime.now(),
      );
      await repo.save(Entry(
        id: 'e1',
        content: 'hi',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dayKey: '2026-11-03',
      ));
      await engine.pushOnce();
      expect(remote.pushes, hasLength(1));
      expect(remote.pushes.single.patches.single.id, 'e1');
      await repo.close();
    });

    test('pull：远端条目合并入本地', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final remote = _FakeRemote();
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
        now: () => DateTime.now(),
      );
      await engine.pullOnce();
      final all = await repo.exportAll();
      expect(
        all.any((e) => e.id == 'e2' && e.content == 'remote'),
        isTrue,
      );
      await repo.close();
    });
  });
}
