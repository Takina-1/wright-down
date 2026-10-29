import 'dart:typed_data';

/// 本应用导出文件名的统一前缀。
///
/// 分享用的临时明文副本也用这个前缀，文件出口据此清理历史遗留的旧副本。
const String kExportFilePrefix = '本地日记-';

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
