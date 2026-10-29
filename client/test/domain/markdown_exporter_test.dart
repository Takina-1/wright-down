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
        entry('c', '第二天的一条', createdAt: DateTime(2026, 10, 29, 7, 0), dayKey: '2026-10-29'),
      ],
      exportedAt: DateTime.utc(2026, 10, 29, 4),
    );
    // 顺序断言在缺少某个标题时会因为 indexOf 返回 -1 而恒真，这里补一条存在性断言。
    expect(markdown, contains('## 2026-10-29'));
    expect(markdown.indexOf('第二天的一条') < markdown.indexOf('较晚的一条'), isTrue);
    expect(markdown.indexOf('较晚的一条') < markdown.indexOf('较早的一条'), isTrue);
    expect(markdown.indexOf('## 2026-10-29') < markdown.indexOf('## 2026-10-28'), isTrue);
  });

  test('utc entries are shown in the local timezone', () {
    // 真实数据从 SQLite 读出来是 UTC，渲染必须换算到设备当前时区。
    final createdAt = DateTime.utc(2026, 10, 28, 20, 5);
    final markdown = exporter.render(
      [entry('a', 'UTC 时刻的一条', createdAt: createdAt)],
      exportedAt: DateTime.utc(2026, 10, 29, 4),
    );
    final local = createdAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    expect(markdown, contains('**$hour:$minute**　UTC 时刻的一条'));
  });

  test('entries are grouped by dayKey rather than by the createdAt date', () {
    final markdown = exporter.render(
      [
        // dayKey 与 createdAt 的本地日期不一致：按 dayKey 应归入 2026-10-28 一组，
        // 若只按 createdAt 全局排序它会被排到 2026-10-29 那条之前。
        entry('m', '归到前一组的条目', createdAt: DateTime(2026, 10, 29, 7, 0), dayKey: '2026-10-28'),
        entry('n', '当天较早的条目', createdAt: DateTime(2026, 10, 29, 6, 0), dayKey: '2026-10-29'),
      ],
      exportedAt: DateTime.utc(2026, 10, 29, 4),
    );
    expect(markdown, contains('## 2026-10-28'));
    expect(markdown, contains('## 2026-10-29'));
    // 分组标题按 dayKey 倒序，而不是按 createdAt 的本地日期倒序。
    expect(markdown.indexOf('## 2026-10-29') < markdown.indexOf('## 2026-10-28'), isTrue);
    // 条目落在自己的 dayKey 分组标题之后。
    expect(markdown.indexOf('**07:00**　归到前一组的条目') > markdown.indexOf('## 2026-10-28'), isTrue);
  });

  test('the exportedAt header records the export time in UTC', () {
    final exportedAt = DateTime(2026, 10, 29, 12, 30, 15);
    final markdown = exporter.render(const [], exportedAt: exportedAt);
    expect(markdown, contains('exportedAt: '));
    expect(markdown, contains('exportedAt: ${exportedAt.toUtc().toIso8601String()}'));
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
