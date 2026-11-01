import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/ui/home_page.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../support/memory_repository.dart';

/// 替身平台：pickFiles 返回一张带字节的假图，readAsBytes 读回这些字节。
class _MockFilePickerPlatform extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  Uint8List bytes = Uint8List(0);

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus status)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    return [_TestPlatformFile(bytes: bytes)];
  }
}

base class _TestPlatformFile extends PlatformFile {
  _TestPlatformFile({required this.bytes}) : uri = Uri.file('/fake/photo.png');

  @override
  final String name = 'photo.png';
  @override
  final Uri uri;
  // bytes 不是 PlatformFile 的继承成员（PlatformFile 有 bytes() 方法，
  // 不是 getter），不能标 override。
  final Uint8List bytes;

  @override
  XFile get xFile => XFile('/fake/photo.png');
  @override
  int? lengthSync() => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
  @override
  Future<int?> length() async => bytes.length;
}

Future<void> _pumpHome(WidgetTester tester, MemoryRepository repo) async {
  await tester.pumpWidget(
    MaterialApp(home: HomePage(repository: repo)),
  );
  await tester.pumpAndSettle();
}

Future<void> _saveContent(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('entry-content')), text);
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  _MockFilePickerPlatform? mock;
  FilePickerPlatform? original;

  setUp(() {
    original = FilePickerPlatform.instance;
    mock = _MockFilePickerPlatform();
    FilePickerPlatform.instance = mock!;
  });

  tearDown(() {
    // 还原默认平台实现，避免污染其它测试。
    if (original != null) FilePickerPlatform.instance = original!;
  });

  testWidgets('记录页有「📷 拍照」入口', (tester) async {
    await _pumpHome(tester, MemoryRepository());
    expect(find.byKey(const Key('photo-entry')), findsOneWidget);
  });

  testWidgets('AC-01: 选图后缩略图显示且落库', (tester) async {
    final repo = MemoryRepository();
    await _pumpHome(tester, repo);
    await _saveContent(tester, '带照片的记录');

    mock!.bytes = Uint8List.fromList([1, 2, 3, 255, 0, 128]);
    await tester.tap(find.byKey(const Key('photo-entry')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('photo-thumbnail')), findsOneWidget);
    expect(repo.entries.values.single.photo, isNotNull);
    expect(repo.entries.values.single.photo!.length, 6);
  });

  testWidgets('AC-02: 点移除按钮清除照片', (tester) async {
    final repo = MemoryRepository();
    await _pumpHome(tester, repo);
    await _saveContent(tester, '带照片的记录');

    mock!.bytes = Uint8List.fromList([1, 2, 3]);
    await tester.tap(find.byKey(const Key('photo-entry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photo-thumbnail')), findsOneWidget);

    await tester.tap(find.byKey(const Key('photo-remove')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('photo-thumbnail')), findsNothing);
    expect(repo.entries.values.single.photo, isNull);
  });

  testWidgets('AC-05: 无照片时不显示缩略图区域', (tester) async {
    await _pumpHome(tester, MemoryRepository());
    expect(find.byKey(const Key('photo-thumbnail')), findsNothing);
  });
}
