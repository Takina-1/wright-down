import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/config/sync_config.dart';

void main() {
  test('未注入 SYNC_BASE_URL 时回落模拟器别名', () {
    expect(syncBaseUrl(), 'http://10.0.2.2:8080');
  });
}
