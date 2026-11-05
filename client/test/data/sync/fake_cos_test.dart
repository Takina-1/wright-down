import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/fake_cos.dart';

void main() {
  test('FakeCos 上传后能下载同内容', () async {
    final oss = FakeCos();
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final key = await oss.upload(bytes);
    expect(key, isA<String>());
    final back = await oss.download(key);
    expect(back, bytes);
    await oss.close();
  });

  test('presign 返回非空 URL', () async {
    final oss = FakeCos();
    final key = await oss.upload(Uint8List.fromList([1]));
    expect(await oss.presign(key), isA<String>());
    await oss.close();
  });

  test('相同内容上传得到相同 key（sha256 去重）', () async {
    final oss = FakeCos();
    final bytes = Uint8List.fromList([10, 20, 30]);
    final k1 = await oss.upload(bytes);
    final k2 = await oss.upload(Uint8List.fromList([10, 20, 30]));
    expect(k1, k2);
    await oss.close();
  });

  test('close 后目录被删除', () async {
    final oss = FakeCos();
    await oss.upload(Uint8List.fromList([1]));
    final root = oss.rootForTest;
    expect(root.existsSync(), isTrue);
    await oss.close();
    expect(root.existsSync(), isFalse);
  });
}
