import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sync_core/sync_core.dart';

/// 照片同步异常：网络失败 / 服务端拒绝统一抛这个，UI 层按 catch 处理。
class PhotoSyncError implements Error {
  const PhotoSyncError(this.message);
  final String message;
  @override
  StackTrace get stackTrace => StackTrace.current;
  @override
  String toString() => 'PhotoSyncError: $message';
}

/// 真机版 COS 网关：照片字节经 ECS 代理读写（D-07 数据路径：客户端 ↔
/// ECS ↔ COS）。凭证只在服务端，客户端零云 SDK、零预签名。
///
/// 上传时 body 为原始字节；服务端算 sha256 并映射到 `photos/<sha256>`，
/// 返回的 key 供客户端落库 photoKey（与 FakeCos 的裸 sha256 语义对齐，
/// 由服务端保证映射一致）。
///
/// [handler] 供测试注入（与 RemoteRepo / EmailPasswordProvider 同款模式）：
/// 给了就绕过真实网络。
class HttpCosGateway implements CosGateway {
  HttpCosGateway({
    required this.baseUrl,
    required this.tokenLoader,
    http.Client? client,
    Future<http.StreamedResponse> Function(http.Request request)? handler,
  }) : _client = client ?? http.Client(),
        this._handler = handler;

  final String baseUrl;
  /// 当前登录 token；未登录返回 null。
  final Future<String?> Function() tokenLoader;
  final http.Client _client;
  final Future<http.StreamedResponse> Function(
      http.Request request)? _handler;

  Future<http.StreamedResponse> _send(http.Request request) {
    final handler = _handler;
    if (handler != null) return handler(request);
    return _client.send(request);
  }

  @override
  Future<String> upload(Uint8List bytes) async {
    final token = await _requireToken();
    final request =
        http.Request('POST', Uri.parse('$baseUrl/sync/photo/upload'));
    request.headers['Authorization'] = 'Bearer $token';
    request.bodyBytes = bytes;
    final response = await _send(request);
    if (response.statusCode != 200) {
      throw PhotoSyncError('upload failed: HTTP ${response.statusCode}');
    }
    final json = jsonDecode(utf8.decode(await _read(response.stream)))
        as Map<String, dynamic>;
    return json['key'] as String;
  }

  @override
  Future<Uint8List> download(String key) async {
    final token = await _requireToken();
    final request = http.Request(
        'GET',
        Uri.parse('$baseUrl/sync/photo/'
            '${Uri.encodeComponent(key)}'));
    request.headers['Authorization'] = 'Bearer $token';
    final response = await _send(request);
    if (response.statusCode == 404) {
      throw PhotoSyncError('photo not found');
    }
    if (response.statusCode != 200) {
      throw PhotoSyncError('download failed: HTTP ${response.statusCode}');
    }
    return Uint8List.fromList(await _read(response.stream));
  }

  @override
  Future<String> presign(String key) async =>
      throw UnsupportedError('presign 不支持：照片经服务端代理，无预签名');

  Future<String> _requireToken() async {
    final token = await tokenLoader();
    if (token == null) throw PhotoSyncError('not logged in');
    return token;
  }

  Future<List<int>> _read(Stream<List<int>> stream) async {
    final chunks = <int>[];
    await for (final c in stream) {
      chunks.addAll(c);
    }
    return chunks;
  }
}
