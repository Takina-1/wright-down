import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';
import 'package:local_diary/src/data/sync/fake_cos.dart';
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
        cos: FakeCos(),
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

    test('push：软删除条目推 deletedAt 标记，删除可传播', () async {
      final repo =
          SqliteEntryRepository(factory: databaseFactoryFfi, path: ':memory:');
      final remote = _FakeRemote();
      final engine = SyncEngine(
        repository: repo,
        remote: remote,
        auth: _FakeAuth(),
        cos: FakeCos(),
        now: () => DateTime.now(),
      );
      await repo.save(Entry(
        id: 'e1',
        content: 'hi',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dayKey: '2026-11-03',
      ));
      await repo.softDelete('e1');
      // 确认软删除已落库：deletedAt 非空，deletedAt stamp > 0。
      final exported = (await repo.exportAll()).firstWhere((e) => e.id == 'e1');
      expect(exported.deletedAt, isNotNull);
      expect(exported.syncStamps['deletedAt'], isNotNull);
      expect(exported.syncStamps['deletedAt']! > 0, isTrue);

      await engine.pushOnce();

      // 软删除条目必须出现在推批次里，且带 deletedAt 字段（值=删除毫秒数，
      // stamp>0）。否则删除永远传不到服务端，设备 B 学不到设备 A 删了条目。
      expect(remote.pushes, hasLength(1));
      final patch = remote.pushes.single.patches.single;
      expect(patch.id, 'e1');
      final deletedAtField = patch.fields['deletedAt'];
      expect(deletedAtField, isNotNull,
          reason: '软删除条目必须带 deletedAt 字段，否则删除无法传播到其他设备');
      expect(deletedAtField!.t > 0, isTrue,
          reason: 'deletedAt stamp 必须 > 0，否则 toSyncEntry 不会输出该字段');
      expect(deletedAtField.v as int, exported.deletedAt!.millisecondsSinceEpoch,
          reason: 'deletedAt 值应等于库中删除时间毫秒数');
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
        cos: FakeCos(),
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
