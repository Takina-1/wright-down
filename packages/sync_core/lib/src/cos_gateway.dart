import 'dart:typed_data';

/// COS 访问抽象。fake 实现开发期用；真机腾讯云 COS 时由服务端代理 COS
/// 读写（本接口不依赖任何 SDK）。
abstract interface class CosGateway {
  /// 上传字节，返回可持久化的 key（sha256）。
  Future<String> upload(Uint8List bytes);

  /// 按 key 下载字节。
  Future<Uint8List> download(String key);

  /// 生成预签名 URL（真机 COS 用；fake 可返回本地路径）。
  Future<String> presign(String key);
}
