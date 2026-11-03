import 'dart:typed_data';

/// OSS 直传抽象。fake 实现开发期用；真机阿里云 OSS 时 presign 由服务端生成、
/// upload/download 由客户端直连 OSS。本接口不依赖任何 SDK。
abstract interface class OSSGateway {
  /// 上传字节，返回可持久化的 key（sha256）。
  Future<String> upload(Uint8List bytes);

  /// 按 key 下载字节。
  Future<Uint8List> download(String key);

  /// 生成预签名 URL（真机 OSS 用；fake 可返回本地路径）。
  Future<String> presign(String key);
}
