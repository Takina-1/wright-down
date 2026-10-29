import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/export/file_gateway.dart';

/// 基于系统文件选择器与分享面板的实现。
///
/// 选文件用 file_selector：Android 上它会把内容读进内存，返回的 XFile 可以直接读。
/// 保存用 file_picker：file_selector 在 Android 上没有实现保存接口。
/// 分享先把内容写进临时目录，再交给系统分享面板。
class SafFileGateway implements FileGateway {
  const SafFileGateway();

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
    final directory = await getTemporaryDirectory();
    final target = File(path.join(directory.path, fileName));
    await target.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(target.path, mimeType: mimeType)],
        title: fileName,
      ),
    );
  }
}
