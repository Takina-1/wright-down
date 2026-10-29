import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/backup_codec.dart';
import 'package:local_diary/src/domain/export/file_gateway.dart';
import 'package:local_diary/src/ui/export_controller.dart';

import '../support/memory_repository.dart';

class FakeFileGateway implements FileGateway {
  String? savedName;
  Uint8List? savedBytes;
  bool cancelSave = false;
  bool cancelPick = false;
  bool failSave = false;
  bool failPick = false;
  bool failShare = false;
  Uint8List? pickResult;
  String? sharedName;

  @override
  Future<String?> saveFile({
    required String suggestedName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    if (failSave) throw StateError('simulated save failure');
    if (cancelSave) return null;
    savedName = suggestedName;
    savedBytes = bytes;
    return 'content://fake/$suggestedName';
  }

  @override
  Future<Uint8List?> pickFile({
    required String mimeType,
    required List<String> extensions,
  }) async {
    if (failPick) throw StateError('simulated pick failure');
    if (cancelPick) return null;
    return pickResult;
  }

  @override
  Future<void> shareFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    if (failShare) throw StateError('simulated share failure');
    sharedName = fileName;
  }
}

void main() {
  final time = DateTime.utc(2026, 10, 28, 8);
  Entry entry(String id, String content, {DateTime? updatedAt}) => Entry(
    id: id,
    content: content,
    createdAt: time,
    updatedAt: updatedAt ?? time,
    dayKey: '2026-10-28',
  );

  test('exporting a backup writes every entry and reports the count', () async {
    final repo = MemoryRepository();
    repo.entries['a'] = entry('a', '第一条');
    repo.entries['b'] = entry('b', '第二条');
    final gateway = FakeFileGateway();
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final ok = await controller.exportBackup();

    expect(ok, isTrue);
    expect(controller.status, ExportStatus.success);
    expect(controller.message, '已导出 2 条');
    expect(gateway.savedName, endsWith('.json'));
    final document = const BackupCodec().decode(
      utf8.decode(gateway.savedBytes!),
    );
    expect(document.entries, hasLength(2));
  });

  test('exporting an empty journal still succeeds and reports zero', () async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway();
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final ok = await controller.exportBackup();

    expect(ok, isTrue);
    expect(controller.status, ExportStatus.success);
    expect(controller.message, '已导出 0 条');
    final document = const BackupCodec().decode(
      utf8.decode(gateway.savedBytes!),
    );
    expect(document.entries, isEmpty);
  });

  test(
    'the exported file name carries seconds so two exports differ',
    () async {
      final repo = MemoryRepository();
      final gateway = FakeFileGateway();
      final controller = ExportController(
        repository: repo,
        fileGateway: gateway,
        now: () => DateTime(2026, 10, 28, 8, 5, 3),
      );

      await controller.exportBackup();

      expect(gateway.savedName, '本地日记-2026-10-28-08-05-03.json');
    },
  );

  test('cancelling the save dialog is not reported as a failure', () async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway()..cancelSave = true;
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final ok = await controller.exportBackup();

    expect(ok, isFalse);
    expect(controller.status, ExportStatus.idle);
    expect(controller.message, isNull);
  });

  test('a failing save reports the export failure message', () async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway()..failSave = true;
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final ok = await controller.exportBackup();

    expect(ok, isFalse);
    expect(controller.status, ExportStatus.failure);
    expect(controller.message, '导出失败，请检查存储空间后重试');
  });

  test('a failed export leaves nothing to share', () async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway();
    final controller = ExportController(repository: repo, fileGateway: gateway);

    // 先成功导出一次，让「分享」入口出现。
    await controller.exportBackup();
    expect(controller.canShare, isTrue);

    // 之后的一次导出失败，不能让人分享到上一次的旧文件。
    gateway.failSave = true;
    final ok = await controller.exportBackup();

    expect(ok, isFalse);
    expect(controller.canShare, isFalse);
    expect(await controller.shareLastExport(), isFalse);
    expect(gateway.sharedName, isNull);
  });

  test('a cancelled export leaves nothing to share', () async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway();
    final controller = ExportController(repository: repo, fileGateway: gateway);

    await controller.exportBackup();
    expect(controller.canShare, isTrue);

    gateway.cancelSave = true;
    final ok = await controller.exportBackup();

    expect(ok, isFalse);
    expect(controller.canShare, isFalse);
  });

  test('a markdown export is offered for sharing after it is saved', () async {
    final repo = MemoryRepository();
    repo.entries['a'] = entry('a', '第一条');
    final gateway = FakeFileGateway();
    final controller = ExportController(repository: repo, fileGateway: gateway);

    await controller.exportMarkdown();

    expect(gateway.savedName, endsWith('.md'));
    expect(controller.canShare, isTrue);
    await controller.shareLastExport();
    expect(gateway.sharedName, endsWith('.md'));
  });

  test('nothing can be shared before the first export', () async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway();
    final controller = ExportController(repository: repo, fileGateway: gateway);

    expect(controller.canShare, isFalse);

    final shared = await controller.shareLastExport();

    expect(shared, isFalse);
    expect(controller.status, ExportStatus.idle);
    expect(controller.message, isNull);
    expect(gateway.sharedName, isNull);
  });

  test('a failing share reports the share failure message', () async {
    final repo = MemoryRepository();
    repo.entries['a'] = entry('a', '第一条');
    final gateway = FakeFileGateway();
    final controller = ExportController(repository: repo, fileGateway: gateway);
    await controller.exportBackup();

    gateway.failShare = true;
    final shared = await controller.shareLastExport();

    expect(shared, isFalse);
    expect(controller.status, ExportStatus.failure);
    expect(controller.message, '分享失败，请重试');
  });

  test(
    'picking a broken backup explains the reason and imports nothing',
    () async {
      final repo = MemoryRepository();
      final gateway = FakeFileGateway()
        ..pickResult = Uint8List.fromList(utf8.encode('不是备份'));
      final controller = ExportController(
        repository: repo,
        fileGateway: gateway,
      );

      final preview = await controller.pickBackup();

      expect(preview, isNull);
      expect(controller.status, ExportStatus.failure);
      expect(controller.message, '这不是本应用的备份文件');
      expect(repo.entries, isEmpty);
    },
  );

  test('an unreadable picked file reports the read failure message', () async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway()..failPick = true;
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final preview = await controller.pickBackup();

    expect(preview, isNull);
    expect(controller.status, ExportStatus.failure);
    expect(controller.message, '无法读取所选文件');
    expect(controller.pendingDocument, isNull);
    expect(repo.entries, isEmpty);
  });

  test('cancelling the file picker is not reported as a failure', () async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway()..cancelPick = true;
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final preview = await controller.pickBackup();

    expect(preview, isNull);
    expect(controller.status, ExportStatus.idle);
    expect(controller.message, isNull);
  });

  test('cancelling the picker drops the previously picked backup', () async {
    final repo = MemoryRepository();
    final backup = const BackupCodec().encode([
      entry('b', '备份新增'),
    ], exportedAt: time);
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(utf8.encode(backup));
    final controller = ExportController(repository: repo, fileGateway: gateway);

    await controller.pickBackup();
    expect(controller.pendingDocument, isNotNull);

    gateway.cancelPick = true;
    final preview = await controller.pickBackup();

    expect(preview, isNull);
    expect(controller.pendingDocument, isNull);
  });

  test('an empty backup is reported without touching local entries', () async {
    final repo = MemoryRepository();
    repo.entries['a'] = entry('a', '本机内容');
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(
        utf8.encode(const BackupCodec().encode([], exportedAt: time)),
      );
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final preview = await controller.pickBackup();

    expect(preview, isNull);
    expect(controller.message, '备份里没有记录');
    expect(controller.pendingDocument, isNull);
    expect(repo.entries, hasLength(1));
    expect(repo.entries['a']!.content, '本机内容');
  });

  test('a picked backup is previewed before it is restored', () async {
    final repo = MemoryRepository();
    repo.entries['a'] = entry('a', '本机内容');
    final backup = const BackupCodec().encode([
      entry('a', '备份较新', updatedAt: time.add(const Duration(minutes: 5))),
      entry('b', '备份新增'),
    ], exportedAt: time);
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(utf8.encode(backup));
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final preview = await controller.pickBackup();

    expect(preview, isNotNull);
    expect(preview!.total, 2);
    expect(preview.inserted, 1);
    expect(preview.updated, 1);
    expect(repo.entries['a']!.content, '本机内容');
  });

  test('confirming a restore merges the backup into the journal', () async {
    final repo = MemoryRepository();
    // 本机：a 与 g 与备份同版本（备份较新 → 更新），c/d/e 本机更新（→ 跳过）。
    repo.entries['a'] = entry('a', '本机内容');
    repo.entries['g'] = entry('g', '本机内容');
    final newer = time.add(const Duration(minutes: 10));
    repo.entries['c'] = entry('c', '本机更新', updatedAt: newer);
    repo.entries['d'] = entry('d', '本机更新', updatedAt: newer);
    repo.entries['e'] = entry('e', '本机更新', updatedAt: newer);
    final backup = const BackupCodec().encode([
      entry('a', '备份较新', updatedAt: time.add(const Duration(minutes: 5))),
      entry('g', '备份较新', updatedAt: time.add(const Duration(minutes: 5))),
      entry('b', '备份新增'),
      entry('c', '备份较旧'),
      entry('d', '备份较旧'),
      entry('e', '备份较旧'),
    ], exportedAt: time);
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(utf8.encode(backup));
    final controller = ExportController(repository: repo, fileGateway: gateway);

    await controller.pickBackup();
    final document = const BackupCodec().decode(
      utf8.decode(gateway.pickResult!),
    );
    final summary = await controller.confirmRestore(document);

    expect(summary, isNotNull);
    expect(summary!.inserted, 1);
    expect(summary.updated, 2);
    expect(summary.skipped, 3);
    expect(repo.entries['b']!.content, '备份新增');
    expect(repo.entries['a']!.content, '备份较新');
    expect(repo.entries['c']!.content, '本机更新');
    expect(controller.message, '恢复完成：新增 1 条，更新 2 条，跳过 3 条');
  });

  test('a failing import reports the restore failure message', () async {
    final repo = MemoryRepository()..failImport = true;
    final backup = const BackupCodec().encode([
      entry('b', '备份新增'),
    ], exportedAt: time);
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(utf8.encode(backup));
    final controller = ExportController(repository: repo, fileGateway: gateway);

    await controller.pickBackup();
    final document = const BackupCodec().decode(
      utf8.decode(gateway.pickResult!),
    );
    final summary = await controller.confirmRestore(document);

    expect(summary, isNull);
    expect(controller.status, ExportStatus.failure);
    expect(controller.message, '恢复失败，未导入任何条目');
    expect(repo.entries, isEmpty);
  });

  test(
    'a disposed controller does not throw when an export finishes',
    () async {
      final repo = MemoryRepository();
      repo.entries['a'] = entry('a', '第一条');
      final gateway = FakeFileGateway();
      final controller = ExportController(
        repository: repo,
        fileGateway: gateway,
      );

      controller.dispose();

      await controller.exportBackup();

      expect(gateway.savedBytes, isNotNull);
    },
  );
}
