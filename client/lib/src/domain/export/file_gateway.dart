import 'dart:typed_data';

/// 文件的出入口。实现放在 platform 层，domain 不依赖任何 SDK。
abstract interface class FileGateway {
  /// 让用户选择保存位置并写入内容，返回保存位置；用户取消时返回 null。
  Future<String?> saveFile({
    required String suggestedName,
    required Uint8List bytes,
    required String mimeType,
  });

  /// 让用户选择一个文件并读出内容；用户取消时返回 null。
  Future<Uint8List?> pickFile({
    required String mimeType,
    required List<String> extensions,
  });

  /// 把内容写进临时文件并交给系统分享面板。
  Future<void> shareFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  });
}
