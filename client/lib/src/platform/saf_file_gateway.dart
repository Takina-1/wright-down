import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/export/file_gateway.dart';

/// 取应用临时目录。测试可以替换成假实现，避免依赖平台插件。
typedef TemporaryDirectoryProvider = Future<Directory> Function();

/// 把临时文件交给系统分享面板。测试可以替换成假实现。
typedef ShareInvoker = Future<void> Function(
  String filePath,
  String fileName,
  String mimeType,
);

/// 基于系统文件选择器与分享面板的实现。
///
/// 选文件用 file_selector：Android 上它会把内容读进内存，返回的 XFile 可以直接读。
/// 保存用 file_picker：file_selector 在 Android 上没有实现保存接口。
/// 分享先把内容写进临时目录，再交给系统分享面板，分享结束后删除这份明文副本。
class SafFileGateway implements FileGateway {
  const SafFileGateway({this.temporaryDirectoryProvider, this.shareInvoker});

  /// 临时目录来源，默认用 path_provider。
  final TemporaryDirectoryProvider? temporaryDirectoryProvider;

  /// 分享调用，默认用 share_plus。
  final ShareInvoker? shareInvoker;

  @override
  Future<String?> saveFile({
    required String suggestedName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: suggestedName,
      bytes: bytes,
      mimeType: mimeType,
    );
    return uri?.toString();
  }

  @override
  Future<Uint8List?> pickFile({
    required String mimeType,
    required List<String> extensions,
  }) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: '本地日记备份',
          extensions: extensions,
          mimeTypes: [mimeType],
        ),
      ],
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> shareFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final directory = await _temporaryDirectory();
    // 写新副本之前先清掉同前缀的旧副本，避免每分享一次就多留一份明文。
    await deleteSharedCopies(directory);
    final target = File(path.join(directory.path, fileName));
    try {
      await target.writeAsBytes(bytes, flush: true);
      await _share(target.path, fileName, mimeType);
    } finally {
      // 分享调用结束后（无论成功与否）删除本次写的明文副本。
      // 分享过程中不能提前删：share_plus 在 Android 上会先把文件复制到它自己的
      // cache/share_plus/ 目录再交给系统面板，返回后我们这份副本就不再被需要。
      await _deleteQuietly(target);
    }
  }

  Future<Directory> _temporaryDirectory() async {
    final provider = temporaryDirectoryProvider;
    if (provider != null) return provider();
    return getTemporaryDirectory();
  }

  Future<void> _share(String filePath, String fileName, String mimeType) async {
    final invoker = shareInvoker;
    if (invoker != null) return invoker(filePath, fileName, mimeType);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath, mimeType: mimeType)],
        title: fileName,
      ),
    );
  }

  /// 删除临时目录里本应用导出用的旧明文副本。
  ///
  /// 只按文件名前缀判断，目录里的其它文件一律不动。
  static Future<void> deleteSharedCopies(
    Directory directory, {
    String prefix = kExportFilePrefix,
  }) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      if (!path.basename(entity.path).startsWith(prefix)) continue;
      await _deleteQuietly(entity);
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 清理失败不能影响分享结果：文件留在缓存目录里由系统回收。
    }
  }
}
