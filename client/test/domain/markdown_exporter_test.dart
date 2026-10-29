import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/markdown_exporter.dart';

void main() {
  const exporter = MarkdownExporter();
  Entry entry(
    String id,
    String content, {
    required DateTime createdAt,
    String dayKey = '2026-10-28',
  }) => Entry(
    id: id,
    content: content,
    createdAt: createdAt,
    updatedAt: createdAt,
    dayKey: dayKey,
  );

  test('an empty journal still produces a readable document', () {
    final markdown = exporter.render(const [], exportedAt: DateTime.utc(2026, 10, 29, 4));
    expect(markdown, contains('# 本地日记导出'));
    expect(markdown, contains('entryCount: 0'));
  });

  test('one entry shows its day and local time', () {
    final markdown = exporter.render(
      [entry('a', '今天走了很远。', createdAt: DateTime(2026, 10, 28, 8, 5))],
      exportedAt: DateTime.utc(2026, 10, 29, 4),
    );
    expect(markdown, contains('## 2026-10-28'));
    expect(markdown, contains('**08:05**　今天走了很远。'));
  });

  test('days and entries are ordered newest first', () {
    final markdown = exporter.render(
      [
        entry('a', '较早的一条', createdAt: DateTime(2026, 10, 28, 9, 12)),
        entry('b', '较晚的一条', createdAt: DateTime(2026, 10, 28, 10, 5)),
        entry('c', '第二天的一条', createdAt: DateTime(2026, 10, 29, 7, 0)),
      ],
      exportedAt: DateTime.utc(2026, 10, 29, 4),
    );
    expect(markdown.indexOf('第二天的一条') < markdown.indexOf('较晚的一条'), isTrue);
    expect(markdown.indexOf('较晚的一条') < markdown.indexOf('较早的一条'), isTrue);
    expect(markdown.indexOf('## 2026-10-29') < markdown.indexOf('## 2026-10-28'), isTrue);
  });

  test('line breaks and markdown symbols stay untouched', () {
    final markdown = exporter.render(
      [entry('a', '第一行\n第二行 # 标题\n- 列表', createdAt: DateTime(2026, 10, 28, 8))],
      exportedAt: DateTime.utc(2026, 10, 29, 4),
    );
    expect(markdown, contains('第一行\n第二行 # 标题\n- 列表'));
  });

  test('entries of the same day are separated by a blank line', () {
    final markdown = exporter.render(
      [
        entry('a', '第一条', createdAt: DateTime(2026, 10, 28, 10)),
        entry('b', '第二条', createdAt: DateTime(2026, 10, 28, 9)),
      ],
      exportedAt: DateTime.utc(2026, 10, 29, 4),
    );
    expect(markdown, contains('**10:00**　第一条\n\n**09:00**　第二条'));
  });
}
