import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/platform/saf_file_gateway.dart';

void main() {
  late Directory temp;
  late List<String> sharedPaths;
  late List<bool> existedDuringShare;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('local_diary_share_');
    sharedPaths = [];
    existedDuringShare = [];
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  SafFileGateway gateway() => SafFileGateway(
    temporaryDirectoryProvider: () async => temp,
    shareInvoker: (filePath, fileName, mimeType) async {
      sharedPaths.add(filePath);
      existedDuringShare.add(File(filePath).existsSync());
    },
  );

  test('the shared copy is deleted after the share call finishes', () async {
    final target = File('${temp.path}/本地日记-2026-10-28-08-05-03.json');

    await gateway().shareFile(
      fileName: '本地日记-2026-10-28-08-05-03.json',
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'application/json',
    );

    // 分享过程中文件必须在：面板要读它。
    expect(existedDuringShare, [isTrue]);
    expect(sharedPaths.single, endsWith('本地日记-2026-10-28-08-05-03.json'));
    // 分享返回后明文副本必须已经删掉。
    expect(target.existsSync(), isFalse);
  });

  test('the shared copy is deleted even when the share call fails', () async {
    final target = File('${temp.path}/本地日记-2026-10-28-08-05-03.md');
    final failing = SafFileGateway(
      temporaryDirectoryProvider: () async => temp,
      shareInvoker: (filePath, fileName, mimeType) async {
        throw StateError('simulated share failure');
      },
    );

    await expectLater(
      failing.shareFile(
        fileName: '本地日记-2026-10-28-08-05-03.md',
        bytes: Uint8List.fromList([1]),
        mimeType: 'text/markdown',
      ),
      throwsStateError,
    );

    expect(target.existsSync(), isFalse);
  });

  test(
    'old copies of the same export are removed before a new one is written',
    () async {
      final old = File('${temp.path}/本地日记-2026-10-27-08-05-03.json')
        ..writeAsBytesSync([1]);
      final other = File('${temp.path}/别的应用的文件.txt')..writeAsBytesSync([2]);

      await gateway().shareFile(
        fileName: '本地日记-2026-10-28-08-05-03.json',
        bytes: Uint8List.fromList([3]),
        mimeType: 'application/json',
      );

      expect(old.existsSync(), isFalse);
      // 临时目录里不是本应用导出的文件不能被误删。
      expect(other.existsSync(), isTrue);
    },
  );

  test('a markdown copy is cleaned up the same way', () async {
    final target = File('${temp.path}/本地日记-2026-10-28-08-05-03.md');

    await gateway().shareFile(
      fileName: '本地日记-2026-10-28-08-05-03.md',
      bytes: Uint8List.fromList([1]),
      mimeType: 'text/markdown',
    );

    expect(target.existsSync(), isFalse);
  });
}
