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
  Uint8List? pickResult;
  String? sharedName;

  @override
  Future<String?> saveFile({
    required String suggestedName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
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
    if (cancelPick) return null;
    return pickResult;
  }

  @override
  Future<void> shareFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
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

  test('cancelling the save dialog is not reported as a failure', () async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway()..cancelSave = true;
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final ok = await controller.exportBackup();

    expect(ok, isFalse);
    expect(controller.status, ExportStatus.idle);
    expect(controller.message, isNull);
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

  test('picking a broken backup explains the reason and imports nothing', () async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(utf8.encode('不是备份'));
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final preview = await controller.pickBackup();

    expect(preview, isNull);
    expect(controller.status, ExportStatus.failure);
    expect(controller.message, '这不是本应用的备份文件');
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

  test('a picked backup is previewed before it is restored', () async {
    final repo = MemoryRepository();
    repo.entries['a'] = entry('a', '本机内容');
    final backup = const BackupCodec().encode(
      [
        entry('a', '备份较新', updatedAt: time.add(const Duration(minutes: 5))),
        entry('b', '备份新增'),
      ],
      exportedAt: time,
    );
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
    final backup = const BackupCodec().encode(
      [entry('b', '备份新增')],
      exportedAt: time,
    );
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
    expect(repo.entries['b']!.content, '备份新增');
    expect(controller.message, '恢复完成：新增 1 条，更新 0 条，跳过 0 条');
  });
}
