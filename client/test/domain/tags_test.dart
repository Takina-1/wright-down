import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/tags.dart';

void main() {
  test('AC-09: trim 每个标签', () {
    expect(normalizeTags(['  旅行 ', '\t读书']), ['旅行', '读书']);
  });

  test('AC-09: 去空字符串与纯空白', () {
    expect(normalizeTags(['旅行', '', '   ', '读书']), ['旅行', '读书']);
  });

  test('AC-09: 去重（保序，保留首次出现）', () {
    expect(normalizeTags(['旅行', '读书', '旅行']), ['旅行', '读书']);
  });

  test('AC-09: 大小写敏感（Travel 与 travel 视为不同）', () {
    expect(normalizeTags(['Travel', 'travel']), ['Travel', 'travel']);
  });

  test('AC-09: 空列表与全空白列表 → 空', () {
    expect(normalizeTags([]), <String>[]);
    expect(normalizeTags(['  ', '']), <String>[]);
  });

  test('AC-09: 不修改入参', () {
    final raw = ['  旅行 ', '旅行'];
    normalizeTags(raw);
    expect(raw, ['  旅行 ', '旅行']);
  });

  test('AC-09: 中文与英文混合标签', () {
    expect(
      normalizeTags(['旅行', 'work', ' 旅行 ', 'reading']),
      ['旅行', 'work', 'reading'],
    );
  });
}
