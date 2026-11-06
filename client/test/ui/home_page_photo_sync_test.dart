import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/sync_engine.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/entry_editor_controller.dart';
import 'package:local_diary/src/ui/home_page.dart';
import 'package:sync_core/sync_core.dart';

import '../support/memory_repository.dart';

/// SyncEngine 依赖的最小远程替身：pull 永远返回空批次、push 空操作。
class _FakeRemote implements SyncRemote {
  @override
  Future<SyncPullResponse> pull(String t, int c) async =>
      SyncPullResponse(cursor: c, entries: []);
  @override
  Future<void> push(String t, SyncPushBatch b) async {}
}

/// SyncEngine 依赖的鉴权替身：current 永远返回已登录态。
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

/// 内存版 COS 替身：upload 返回递增 key 并记下字节，download 按 key 取回。
///
/// 不用 [FakeCos]（真实文件 I/O）的原因：widget 测试跑在 FakeAsync 上，
/// `File.readAsBytes` 的延续不会在 `pumpAndSettle` 时排空——只有
/// `tester.runAsync` 直接 await 才能拿到结果，而 composer 内部的
/// `cos.download` 是 fire-and-forget，延续永远排不上空。预解析的
/// `Future.value` 走微任务队列，能被 `pumpAndSettle` 排空，行为等价
/// （按 key 返回字节），适合驱动 UI。真实 I/O 路径由 sync_engine 层的
/// `test()` 覆盖（见 sync_engine_photo_test.dart）。
class _InMemoryCos implements CosGateway {
  final Map<String, Uint8List> _store = {};
  int _seq = 0;

  @override
  Future<String> upload(Uint8List bytes) async {
    final key = 'key-$_seq';
    _seq++;
    _store[key] = bytes;
    return key;
  }

  @override
  Future<Uint8List> download(String key) async =>
      _store[key] ?? Uint8List(0);

  @override
  Future<String> presign(String key) async => 'fake://$key';
}

void main() {
  group('EntryEditorController photoKey', () {
    EntryEditorController makeController(MemoryRepository repo) =>
        EntryEditorController(
      repository: repo,
      idGenerator: () => 'new-id',
      now: () => DateTime.utc(2026, 10, 28, 8),
    );

    test('编辑带 photoKey 但 photo=null 的条目，保存后 photoKey 不丢失', () async {
      final repo = MemoryRepository();
      final controller = makeController(repo);
      await controller.edit(Entry(
        id: 'e1',
        content: '原始内容',
        createdAt: DateTime.utc(2026, 10, 28, 8),
        updatedAt: DateTime.utc(2026, 10, 28, 8),
        dayKey: '2026-10-28',
        photo: null,
        photoKey: 'some-oss-key',
      ));
      controller.updateContent('修改后的内容');
      await controller.flush();
      final saved = repo.entries['e1']!;
      expect(saved.content, '修改后的内容');
      expect(saved.photoKey, 'some-oss-key',
          reason: '编辑不应清空 photoKey——否则跨设备照片下载会断链');
      controller.dispose();
    });

    test('编辑带 photoKey 和 photo 的条目，保存后两者都不丢失', () async {
      final repo = MemoryRepository();
      final controller = makeController(repo);
      final photo = Uint8List.fromList([1, 2, 3]);
      await controller.edit(Entry(
        id: 'e1',
        content: '原始内容',
        createdAt: DateTime.utc(2026, 10, 28, 8),
        updatedAt: DateTime.utc(2026, 10, 28, 8),
        dayKey: '2026-10-28',
        photo: photo,
        photoKey: 'some-oss-key',
      ));
      controller.updateContent('修改后的内容');
      await controller.flush();
      final saved = repo.entries['e1']!;
      expect(saved.photo, photo);
      expect(saved.photoKey, 'some-oss-key');
      controller.dispose();
    });

    test('新记录 photoKey 为 null', () async {
      final repo = MemoryRepository();
      final controller = makeController(repo);
      await controller.newEntry();
      expect(controller.photoKey, isNull);
      controller.dispose();
    });

    test('setPhoto 保留既有 photoKey', () async {
      final repo = MemoryRepository();
      final controller = makeController(repo);
      await controller.edit(Entry(
        id: 'e1',
        content: '原始内容',
        createdAt: DateTime.utc(2026, 10, 28, 8),
        updatedAt: DateTime.utc(2026, 10, 28, 8),
        dayKey: '2026-10-28',
        photo: null,
        photoKey: 'some-oss-key',
      ));
      controller.setPhoto(Uint8List.fromList([4, 5, 6]));
      await controller.flush();
      final saved = repo.entries['e1']!;
      expect(saved.photo, isNotNull);
      expect(saved.photoKey, 'some-oss-key',
          reason: 'setPhoto 不应清空既有 photoKey');
      controller.dispose();
    });
  });

  group('composer 照片缩略图从 photoKey 下载', () {
    testWidgets('编辑带 photoKey 但 photo=null 的条目，composer 显示缩略图',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 3000);
      addTearDown(tester.view.reset);

      final oss = _InMemoryCos();
      final photoBytes = Uint8List.fromList([42, 43, 44]);
      final key = await oss.upload(photoBytes);

      final repo = MemoryRepository();
      final created = DateTime.utc(2026, 10, 28, 8);
      await repo.save(Entry(
        id: 'e1',
        content: '远端照片记录',
        createdAt: created,
        updatedAt: created,
        dayKey: '2026-10-28',
        photo: null,
        photoKey: key,
      ));

      final engine = SyncEngine(
        repository: repo,
        remote: _FakeRemote(),
        auth: _FakeAuth(),
        cos: oss,
        now: () => DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(home: HomePage(repository: repo, syncEngine: engine)),
      );
      await tester.pumpAndSettle();

      // 切到回顾页。
      await tester.tap(find.text('回顾'));
      await tester.pumpAndSettle();

      // 点条目进入编辑（composer 自动切回）。
      await tester.tap(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('远端照片记录'),
        ),
      );
      // 下载是微任务（_InMemoryCos 预解析 Future），pumpAndSettle 排空后
      // _fetchRemotePhoto 延续 setState 显示缩略图。
      await tester.pumpAndSettle();

      // 停掉同步引擎：triggerPush 的 30 秒防抖定时器若不清掉，测试结束
      // 时 FakeAsync 会报 "timersPending"。
      engine.stop();

      expect(find.byKey(const Key('photo-thumbnail')), findsOneWidget);
    });
  });
}
