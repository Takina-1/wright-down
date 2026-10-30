import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/mood.dart';

void main() {
  group('Mood 标记与显示映射', () {
    test('5 种心情的标记、emoji、文字一一对应', () {
      const table = <Mood, List<String>>{
        Mood.happy: ['😄', '开心'],
        Mood.good: ['😊', '不错'],
        Mood.neutral: ['🙂', '一般'],
        Mood.plain: ['😐', '平淡'],
        Mood.sad: ['😢', '难过'],
      };
      for (final entry in table.entries) {
        expect(emojiOf(entry.key.name), entry.value[0]);
        expect(labelOf(entry.key.name), entry.value[1]);
      }
      expect(allMoods, hasLength(5));
    });

    test('parseMood 对合法标记返回对应枚举', () {
      expect(parseMood('happy'), Mood.happy);
      expect(parseMood('good'), Mood.good);
      expect(parseMood('neutral'), Mood.neutral);
      expect(parseMood('plain'), Mood.plain);
      expect(parseMood('sad'), Mood.sad);
    });

    test('parseMood 对 null、未知标记、空串、大小写不匹配、emoji 返回 null', () {
      expect(parseMood(null), isNull);
      expect(parseMood(''), isNull);
      expect(parseMood('angry'), isNull);
      expect(parseMood('Happy'), isNull); // 大小写敏感
      expect(parseMood('😄'), isNull);   // emoji 不是合法标记
    });

    test('emojiOf 与 labelOf 对 null 与非法标记返回空串', () {
      expect(emojiOf(null), '');
      expect(labelOf(null), '');
      expect(emojiOf('angry'), '');
      expect(labelOf('angry'), '');
    });
  });
}
