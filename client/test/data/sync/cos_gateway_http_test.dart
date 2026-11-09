import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_diary/src/data/sync/cos_gateway_http.dart';

http.StreamedResponse _json(String s, int code) => http.StreamedResponse(
      Stream<List<int>>.fromIterable([utf8.encode(s)]),
      code,
      headers: {'content-type': 'application/json'},
    );

http.StreamedResponse _bytes(Uint8List data, int code) =>
    http.StreamedResponse(
        Stream<List<int>>.fromIterable([data]), code);

void main() {
  group('HttpCosGateway', () {
    test('upload：POST /sync/photo/upload，携带 Bearer token，返回服务端 key',
        () async {
      http.Request? seen;
      final gateway = HttpCosGateway(
        baseUrl: 'http://x',
        tokenLoader: () async => 'tok',
        handler: (req) async {
          seen = req;
          return _json('{"ok":true,"key":"photos/abc"}', 200);
        },
      );
      final key = await gateway.upload(Uint8List.fromList('data'.codeUnits));
      expect(key, 'photos/abc');
      expect(seen!.method, 'POST');
      expect(seen!.url.toString(), 'http://x/sync/photo/upload');
      expect(seen!.headers['Authorization'], 'Bearer tok');
      expect(seen!.bodyBytes, Uint8List.fromList('data'.codeUnits));
    });

    test('download：GET /sync/photo/<encoded>，返回字节', () async {
      final data = Uint8List.fromList(List.filled(10, 5));
      http.Request? seen;
      final gateway = HttpCosGateway(
        baseUrl: 'http://x',
        tokenLoader: () async => 'tok',
        handler: (req) async {
          seen = req;
          return _bytes(data, 200);
        },
      );
      final got = await gateway.download('photos/abc');
      expect(got, equals(data));
      expect(seen!.url.toString(), 'http://x/sync/photo/photos%2Fabc');
    });

    test('下载 404 → PhotoSyncError', () async {
      final gateway = HttpCosGateway(
        baseUrl: 'http://x',
        tokenLoader: () async => 'tok',
        handler: (_) async => _bytes(Uint8List(0), 404),
      );
      await expectLater(
          gateway.download('photos/x'), throwsA(isA<PhotoSyncError>()));
    });

    test('未登录 → PhotoSyncError（不发请求）', () async {
      var called = false;
      final gateway = HttpCosGateway(
        baseUrl: 'http://x',
        tokenLoader: () async => null,
        handler: (_) async {
          called = true;
          return _json('{}', 200);
        },
      );
      await expectLater(
          gateway.upload(Uint8List(0)), throwsA(isA<PhotoSyncError>()));
      expect(called, isFalse);
    });

    test('presign 抛 UnsupportedError', () async {
      final gateway = HttpCosGateway(
        baseUrl: 'http://x',
        tokenLoader: () async => 'tok',
      );
      await expectLater(
          gateway.presign('k'), throwsA(isA<UnsupportedError>()));
    });
  });
}
