import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import 'handlers.dart';
import 'sync_store.dart';

/// 照片对象存储代理：客户端 ↔ ECS ↔ 腾讯云 COS（D-07 数据路径）。
///
/// 客户端永远拿不到密钥：本文件持有的是唯一的 COS 凭证，且只用于服务端
/// 签名代理读写。对象路径约定：客户端 photoKey 是裸 sha256，服务端把
/// 其映射为 `${prefix}/<sha256>`（与 deploy/cam-policy.json 的 PREFIX
/// 前缀一致，缺省 `photos`）。
///
/// 签名算法对照腾讯云官方 SDK（tencentyun/cos-go-sdk-v5 `auth.go`）：
/// - FormatString = `method\nuri\nquery\nheaders\n`（method 小写，headers
///   是按字典序排序的 `name=value` URL 编码串，**结尾带 \n**，无 body hash）
/// - StringToSign = `sha1\n<signTime>\n<hexLower(sha1(FormatString))>\n`
/// - signingKey = hexLower(HMAC-SHA1(secretKey, signTime))
/// - signature  = hexLower(HMAC-SHA1(signingKey, StringToSign))
/// - Authorization = q-sign-algorithm=sha1&q-ak=&q-sign-time=&q-key-time=
///   &q-header-list=&q-url-param-list=&q-signature=
/// - signTime / keyTime 格式为 `<startUnix>;<endUnix>`（秒级、`;` 分隔）
///
/// Dart 生态没有纯 Dart 的官方 COS SDK，此处仅用 package:crypto 自行签名，
/// 不引入任何非官方依赖。

/// COS 凭证 + 路径前缀。环境变量：COS_BUCKET / COS_SECRET_ID /
/// COS_SECRET_KEY / COS_PREFIX（缺省 `photos`）。凭证绝不下发给客户端。
class CosCredentials {
  const CosCredentials({
    required this.bucket,
    required this.secretId,
    required this.secretKey,
    this.prefix = 'photos',
  });

  final String bucket;
  final String secretId;
  final String secretKey;
  final String prefix;

  /// 广州地域的公网访问域名（桶名带 -<APPID> 后缀，直接作为 Host）。
  String get host => '$bucket.cos.ap-guangzhou.myqcloud.com';

  /// 从环境变量构造；缺任一必填项返回 null（调用方回落 FakeCos 或跳过挂载）。
  static CosCredentials? fromEnv(Map<String, String> env) {
    final bucket = env['COS_BUCKET'];
    final secretId = env['COS_SECRET_ID'];
    final secretKey = env['COS_SECRET_KEY'];
    if (bucket is! String || secretId is! String || secretKey is! String ||
        bucket.isEmpty || secretId.isEmpty || secretKey.isEmpty) {
      return null;
    }
    final prefix = env['COS_PREFIX'];
    return CosCredentials(
      bucket: bucket,
      secretId: secretId,
      secretKey: secretKey,
      prefix: prefix is String && prefix.isNotEmpty ? prefix : 'photos',
    );
  }
}

/// Digest / List<int> → 小写 hex（sha1 摘要长度固定 40）。
String _hexLower(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 计算腾讯云 COS v1 签名所需的请求头。
///
/// signTime / keyTime 必须一致（本实现固定一致），startUnix/endUnix 为
/// 秒级。method 会被小写化参与签名，与 Go SDK 的 newAuthorization 一致。
/// 返回的头集合既含 Authorization 也含 Content-Type/Host——签名要求请求里
/// 实际携带同值的头，因此调用方必须把返回值整组加进真实请求。
///
/// [contentLength] 非空时（PUT 等有体请求）参与签名并计入 header-list，
/// 与官方 SDK 对 Content-Length 的处理一致。
Map<String, String> cosV1AuthHeaders({
  required String method,
  required String uriPath,
  required String host,
  required String contentType,
  required String secretId,
  required String secretKey,
  required int signTimeStart,
  required int signTimeEnd,
  int? contentLength,
}) {
  final keyTime = '$signTimeStart;$signTimeEnd';
  final signKey = _hexLower(
      Hmac(sha1, utf8.encode(secretKey)).convert(utf8.encode(keyTime)).bytes);

  // 参与签名的头集合（对照 Go SDK NeedSignHeaders）：host + content-type
  // （+ content-length，PUT 时）。与请求实际携带的头一致，缺哪个都会 403。
  final canonical = <String, String>{
    'content-type': contentType,
    'host': host,
  };
  if (contentLength != null) canonical['content-length'] = '$contentLength';
  final sortedKeys = canonical.keys.toList()..sort();
  final formatHeaders = sortedKeys
      .map((k) =>
          '${Uri.encodeComponent(k)}=${Uri.encodeComponent(canonical[k]!)}')
      .join('&');

  final formatString = '${method.toLowerCase()}\n$uriPath\n\n$formatHeaders\n';
  final stringToSign =
      'sha1\n$keyTime\n${_hexLower(sha1.convert(utf8.encode(formatString)).bytes)}\n';
  final signature = _hexLower(
      Hmac(sha1, utf8.encode(signKey)).convert(utf8.encode(stringToSign)).bytes);

  return {
    'Authorization':
        'q-sign-algorithm=sha1&q-ak=$secretId&q-sign-time=$keyTime'
        '&q-key-time=$keyTime'
        '&q-header-list=${sortedKeys.join(";")}'
        '&q-url-param-list='
        '&q-signature=$signature',
    'Content-Type': contentType,
    'Host': host,
  };
}

/// 照片端点需要的两个参数：文件路径前缀 + 对象读写通道（抽象，便于测试注入）。
class PhotoGateway {
  PhotoGateway({required this.prefix, required this.cos});
  final String prefix;
  final CosObjectStore cos;
}

/// 对象读写抽象：真实实现 [HttpCosStore]，测试用替身注入。
abstract interface class CosObjectStore {
  /// PUT 对象，返回 COS HTTP 状态码（200 表示成功）。
  Future<int> putObject(String key, Uint8List bytes,
      {required String contentType});

  /// GET 对象字节；404 返回 null。
  Future<Uint8List?> getObject(String key);
}

/// 基于 package:http 的 COS 调用实现（与客户端同栈）。
class HttpCosStore implements CosObjectStore {
  HttpCosStore(this._credentials, {http.Client? client})
      : _client = client ?? http.Client();

  final CosCredentials _credentials;
  final http.Client _client;

  @override
  Future<int> putObject(String key, Uint8List bytes,
      {required String contentType}) async {
    final request =
        http.Request('PUT', Uri.parse('https://${_credentials.host}$key'));
    _applyHeaders(request,
        _sign('PUT', key, contentType, contentLength: bytes.length));
    request.bodyBytes = bytes;
    final response = await _client.send(request);
    await response.stream.drain<void>();
    return response.statusCode;
  }

  @override
  Future<Uint8List?> getObject(String key) async {
    final request =
        http.Request('GET', Uri.parse('https://${_credentials.host}$key'));
    _applyHeaders(request,
        _sign('GET', key, 'application/octet-stream'));
    final response = await _client.send(request);
    if (response.statusCode == 404) {
      await response.stream.drain<void>();
      return null;
    }
    final chunks = <int>[];
    await for (final c in response.stream) {
      chunks.addAll(c);
    }
    return Uint8List.fromList(chunks);
  }

  void _applyHeaders(http.Request request, Map<String, String> headers) {
    for (final e in headers.entries) {
      request.headers[e.key] = e.value;
    }
  }

  Map<String, String> _sign(
      String method, String key, String contentType,
      {int? contentLength}) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return cosV1AuthHeaders(
      method: method,
      uriPath: key,
      host: _credentials.host,
      contentType: contentType,
      secretId: _credentials.secretId,
      secretKey: _credentials.secretKey,
      signTimeStart: now,
      signTimeEnd: now + _signExpireSeconds,
      contentLength: contentLength,
    );
  }
}

/// 签名有效期（秒），与腾讯云建议一致：密钥只在短窗口内有效，被截获
/// 也只能短时使用；签名窗固定即可。
const int _signExpireSeconds = 900;

// ---------------------------------------------------------------------------
// shelf 路由 handler（照片上传 / 下载 / 判存）
// ---------------------------------------------------------------------------

/// 上传 handler：body = 照片字节；服务端算 sha256，映射到 `<prefix>/<sha256>`
/// 后签名 PUT COS；成功后返回该 key 供客户端落库 photoKey。
Handler photoUploadHandler(SyncStore store, PhotoGateway gateway) =>
    (req) async {
  final token = bearerToken(req);
  if (token == null) return _photoErr(401, 'missing token');
  final userId = await store.userIdForToken(token);
  if (userId == null) return _photoErr(401, 'invalid token');

  final chunks = <int>[];
  await for (final c in req.read()) {
    chunks.addAll(c);
  }
  final bytes = Uint8List.fromList(chunks);
  final key = '${gateway.prefix}/${sha256.convert(bytes).toString()}';
  int code;
  try {
    code = await gateway.cos.putObject(key, bytes,
        contentType: 'application/octet-stream');
  } on Object catch (_) {
    return _photoErr(502, 'cos unavailable');
  }
  if (code != 200) return _photoErr(code, 'cos upload failed');
  return Response.ok(jsonEncode({'ok': true, 'key': key}),
      headers: {'content-type': 'application/json'});
};

/// 下载 handler：GET /sync/photo/<key>；透传字节；键不存在（COS 404）返回 404。
Handler photoDownloadHandler(SyncStore store, PhotoGateway gateway) =>
    (req) async {
  final token = bearerToken(req);
  if (token == null) return _photoErr(401, 'missing token');
  final userId = await store.userIdForToken(token);
  if (userId == null) return _photoErr(401, 'invalid token');

  final key = _keyFromUri(req.requestedUri.path);
  if (key.isEmpty) return _photoErr(400, 'missing key');
  Uint8List? bytes;
  try {
    bytes = await gateway.cos.getObject(key);
  } on Object catch (_) {
    return _photoErr(502, 'cos unavailable');
  }
  if (bytes == null) return _photoErr(404, 'not found');
  return Response.ok(bytes,
      headers: {'content-type': 'application/octet-stream'});
};

/// 判存 handler（秒传）：HEAD /sync/photo/<key> → 200 / 404。
Handler photoExistsHandler(SyncStore store, PhotoGateway gateway) =>
    (req) async {
  final token = bearerToken(req);
  if (token == null) return _photoErr(401, 'missing token');
  final userId = await store.userIdForToken(token);
  if (userId == null) return _photoErr(401, 'invalid token');

  final key = _keyFromUri(req.requestedUri.path);
  if (key.isEmpty) return _photoErr(400, 'missing key');
  Uint8List? bytes;
  try {
    bytes = await gateway.cos.getObject(key);
  } on Object catch (_) {
    return _photoErr(502, 'cos unavailable');
  }
  if (bytes == null) return _photoErr(404, 'not found');
  return Response.ok('', headers: {'x-photo-exists': '1'});
};

/// 从 `/sync/photo/<key...>` 提取对象 key（URL 解码）。
String _keyFromUri(String path) {
  const marker = '/sync/photo/';
  if (!path.startsWith(marker)) return '';
  return Uri.decodeComponent(path.substring(marker.length));
}

Response _photoErr(int status, String msg) => Response(status, body: msg,
    headers: {'content-type': 'application/json'});
