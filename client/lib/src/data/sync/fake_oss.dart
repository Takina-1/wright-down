import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sync_core/sync_core.dart';

/// 本地文件系统实现 [OSSGateway]（开发/测试用）。
///
/// upload 计算字节的 sha256 作为 key，写入 `<root>/<key>`；download 按 key
/// 读取字节；presign 返回 `fake://<root>/<key>` 假 URL。不依赖任何云 SDK。
///
/// [root] 默认在系统临时目录下创建；可通过构造参数注入指定目录（如测试夹具）。
/// [close] 删除底层目录——仅用于开发/测试清理，勿对真实项目目录调用。
class FakeOSS implements OSSGateway {
  FakeOSS({Directory? root})
      : _root = root ?? Directory.systemTemp.createTempSync('fakeoss');

  final Directory _root;

  /// 测试夹具：暴露底层目录以便断言 close 后是否被删除。
  Directory get rootForTest => _root;

  @override
  Future<String> upload(Uint8List bytes) async {
    if (!_root.existsSync()) _root.createSync(recursive: true);
    final key = sha256.convert(bytes).toString();
    await File('${_root.path}/$key').writeAsBytes(bytes);
    return key;
  }

  @override
  Future<Uint8List> download(String key) async {
    return Uint8List.fromList(await File('${_root.path}/$key').readAsBytes());
  }

  @override
  Future<String> presign(String key) async => 'fake://${_root.path}/$key';

  /// 删除底层目录。目录不存在时静默返回，可安全重复调用。
  Future<void> close() async {
    if (_root.existsSync()) await _root.delete(recursive: true);
  }
}
