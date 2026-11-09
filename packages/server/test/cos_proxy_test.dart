import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:server/server.dart';

/// 假 COS 通道：不触网，记录 put/get 调用供断言。
class _FakeCosStore implements CosObjectStore {
  final Map<String, Uint8List> objects = {};
  final List<Map<String, dynamic>> puts = [];
  final List<String> gets = [];

  @override
  Future<int> putObject(String key, Uint8List bytes,
      {required String contentType}) async {
    puts.add({'key': key, 'bytes': bytes, 'contentType': contentType});
    objects[key] = bytes;
    return 200;
  }

  @override
  Future<Uint8List?> getObject(String key) async {
    gets.add(key);
    return objects[key];
  }
}

Request _req(String method, String path,
    {Map<String, String>? headers, Object? body}) =>
    Request(method, Uri.parse('http://localhost$path'),
        headers: headers ?? {}, body: body ?? '');

Future<Map<String, dynamic>> _json(Response r) async =>
    jsonDecode(await r.readAsString()) as Map<String, dynamic>;

void main() {
  group('cosV1 签名', () {
    const ak = 'AKIDTEST';
    const sk = 'secretTEST';
    const host = 'my-bucket-1300000000.cos.ap-guangzhou.myqcloud.com';

    Map<String, String> _sign(
        {String method = 'PUT',
        String path = '/photos/abc',
        String host = host,
        String contentType = 'application/octet-stream',
        int start = 1700000000,
        int end = 1700000900}) =>
        cosV1AuthHeaders(
          method: method,
          uriPath: path,
          host: host,
          contentType: contentType,
          secretId: ak,
          secretKey: sk,
          signTimeStart: start,
          signTimeEnd: end,
        );

    test('相同输入签名稳定（可复现）', () {
      final a = _sign();
      final b = _sign();
      expect(a['Authorization'], b['Authorization']);
    });

    test('Authorization 结构：六参数 + 40 位十六进制签名', () {
      final h = _sign()['Authorization']!;
      final parts = h.split('&');
      expect(parts[0], 'q-sign-algorithm=sha1');
      expect(parts[1], 'q-ak=$ak');
      expect(parts[2], 'q-sign-time=1700000000;1700000900');
      expect(parts[3], 'q-key-time=1700000000;1700000900');
      expect(parts[4], 'q-header-list=content-type;host');
      expect(parts[5], 'q-url-param-list=');
      expect(parts.singleWhere((p) => p.startsWith('q-signature='))
              .substring('q-signature='.length).length,
          40);
    });

    test('method 参与签名：PUT 与 GET 签名不同', () {
      final put = _sign(method: 'PUT')['Authorization']!;
      final get = _sign(method: 'GET')['Authorization']!;
      expect(put, isNot(get));
    });

    test('host 参与签名：桶域名不同签名不同', () {
      final r = _sign(host: 'other.cos.ap-guangzhou.myqcloud.com');
      expect(r['Authorization'], isNot(_sign()['Authorization']));
    });

    test('密钥不同签名不同', () {
      expect(() => cosV1AuthHeaders(
            method: 'PUT',
            uriPath: '/x',
            host: host,
            contentType: 'application/octet-stream',
            secretId: 'AKIDOTHER',
            secretKey: 'othersecret',
            signTimeStart: 1,
            signTimeEnd: 901,
          ).toString(),
          isNot(_sign(start: 1, end: 901).toString()));
    });

    test('过期窗口变化签名变化', () {
      final early = _sign(start: 100, end: 1000);
      final late = _sign(start: 200, end: 2000);
      expect(early['Authorization'], isNot(late['Authorization']));
    });

    test('返回的头包含完整签名三件套', () {
      final headers = _sign();
      expect(headers.keys.toSet(),
          containsAll(['Authorization', 'Content-Type', 'Host']));
      expect(headers['Host'], host);
    });

    test('contentLength 参与签名：header-list 含 content-length', () {
      final h = cosV1AuthHeaders(
        method: 'PUT',
        uriPath: '/photos/abc',
        host: host,
        contentType: 'application/octet-stream',
        secretId: ak,
        secretKey: sk,
        signTimeStart: 1700000000,
        signTimeEnd: 1700000900,
        contentLength: 27,
      );
      final auth = h['Authorization']!;
      expect(auth, contains('q-header-list=content-length;content-type;host'));
    });

    test('cosSignForRequest：uriPath 带前导斜杠，与不带斜杠的签名不同', () {
      // 回归：签名 uriPath 漏前导 '/' 曾导致真实 COS 返回 403。
      const creds = CosCredentials(
          bucket: 'my-bucket-1300000000', secretId: ak, secretKey: sk);
      final a = cosSignForRequest(
        creds, 'PUT', 'photos/abc', 'application/octet-stream',
        contentLength: 27,
        signTimeStart: 1700000000,
        signTimeEnd: 1700000900,
      );
      final withoutSlash = cosV1AuthHeaders(
        method: 'PUT', uriPath: 'photos/abc', host: host,
        contentType: 'application/octet-stream', secretId: ak, secretKey: sk,
        signTimeStart: 1700000000, signTimeEnd: 1700000900,
        contentLength: 27,
      );
      final withSlash = cosV1AuthHeaders(
        method: 'PUT', uriPath: '/photos/abc', host: host,
        contentType: 'application/octet-stream', secretId: ak, secretKey: sk,
        signTimeStart: 1700000000, signTimeEnd: 1700000900,
        contentLength: 27,
      );
      expect(a['Authorization'], isNot(withoutSlash['Authorization']));
      expect(a['Authorization'], withSlash['Authorization']);
    });
  });

  group('照片代理端点', () {
    final store = FakeSyncStore();
    final cos = _FakeCosStore();
    final gateway = PhotoGateway(prefix: 'photos', cos: cos);

    test('上传：返回 photos/<sha256>，字节与内容类型一致', () async {
      final r = await store.register('u@b.com', 'pw');
      final data = Uint8List.fromList('hello-photo'.codeUnits);
      final req = _req('POST', '/sync/photo/upload',
          headers: {'authorization': 'Bearer ${r.token}'},
          body: Stream<List<int>>.fromIterable([data]));
      final res = await photoUploadHandler(store, gateway)(req);
      expect(res.statusCode, 200);
      final j = await _json(res);
      expect(j['ok'], isTrue);
      final key = j['key'] as String;
      expect(key, startsWith('photos/'));
      expect(key.endsWith('${sha256.convert(data).toString()}'), isTrue);
      expect(cos.puts.single['key'], key);
      expect(cos.puts.single['bytes'], data);
      expect(cos.puts.single['contentType'], 'application/octet-stream');
    });

    test('下载：透传字节；未知 key 返回 404', () async {
      final r = await store.register('d@b.com', 'pw');
      final key = 'photos/deadbeef';
      final data = Uint8List.fromList(List.filled(64, 7));
      cos.objects[key] = data;

      final good = _req('GET', '/sync/photo/$key',
          headers: {'authorization': 'Bearer ${r.token}'});
      final res = await photoDownloadHandler(store, gateway)(good);
      expect(res.statusCode, 200);
      final read = <int>[];
      await for (final c in res.read()) read.addAll(c);
      expect(read, equals(data.toList()));
      expect(res.headers['content-type'], 'application/octet-stream');

      final bad = _req('GET', '/sync/photo/photos/missing',
          headers: {'authorization': 'Bearer ${r.token}'});
      final badRes = await photoDownloadHandler(store, gateway)(bad);
      expect(badRes.statusCode, 404);
    });

    test('URL 编码的 key 能被解码：photos%2F<sha>', () async {
      final r = await store.register('e@b.com', 'pw');
      final key = 'photos/aabbcc';
      cos.objects[key] = Uint8List.fromList('x'.codeUnits);
      final req = _req('GET', '/sync/photo/photos%2Faabbcc',
          headers: {'authorization': 'Bearer ${r.token}'});
      final res = await photoDownloadHandler(store, gateway)(req);
      expect(res.statusCode, 200);
      // group 内共享 _FakeCosStore，取最近一次 get 调用。
      expect(cos.gets.last, key);
    });

    test('判存 HEAD：存在 200 / 不存在 404', () async {
      final r = await store.register('f@b.com', 'pw');
      cos.objects['photos/x'] = Uint8List.fromList('v'.codeUnits);
      final a = _req('HEAD', '/sync/photo/photos/x',
          headers: {'authorization': 'Bearer ${r.token}'});
      expect((await photoExistsHandler(store, gateway)(a)).statusCode, 200);
      final b = _req('HEAD', '/sync/photo/photos/absent',
          headers: {'authorization': 'Bearer ${r.token}'});
      expect((await photoExistsHandler(store, gateway)(b)).statusCode, 404);
    });

    test('鉴权：无 token / 错 token 返回 401', () async {
      final store2 = FakeSyncStore();
      final g2 = PhotoGateway(prefix: 'photos', cos: _FakeCosStore());
      final a = await photoUploadHandler(store2, g2)(
          _req('POST', '/sync/photo/upload', body: Stream<List<int>>.fromIterable([Uint8List.fromList('x'.codeUnits)])));
      expect(a.statusCode, 401);
      final b = await photoDownloadHandler(store2, g2)(
          _req('GET', '/sync/photo/photos/any'));
      expect(b.statusCode, 401);

      await store2.register('g@b.com', 'pw');
      final badReq = _req('GET', '/sync/photo/photos/any',
          headers: {'authorization': 'Bearer wrongtoken'});
      expect((await photoDownloadHandler(store2, g2)(badReq)).statusCode, 401);
    });

    test('createApp：无凭证不挂照片路由（404）', () async {
      final app = createApp(store, cos: null);
      final res = await app(_req('GET', '/sync/photo/photos/x'));
      expect(res.statusCode, 404);
    });

    test('createApp：凭证齐全挂照片路由（上传 200）', () async {
      final r = await store.register('h@b.com', 'pw');
      final fake = _FakeCosStore();
      // 注入假网关验证路由挂载与 dispatch，避开网络。
      final app = createApp(
        store,
        cos: const CosCredentials(
            bucket: 'my-bucket',
            secretId: 'AKID',
            secretKey: 'SK',
            prefix: 'photos'),
        gateway: PhotoGateway(prefix: 'photos', cos: fake),
      );
      final res = await app(_req('POST', '/sync/photo/upload',
          headers: {'authorization': 'Bearer ${r.token}'},
          body: Stream<List<int>>.fromIterable([Uint8List.fromList('x'.codeUnits)])));
      expect(res.statusCode, 200);
      final j = await _json(res);
      expect(j['key'], startsWith('photos/'));
    });
  });
}
