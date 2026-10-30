import '../entry.dart';

/// 把条目渲染成可阅读的 Markdown。正文原样输出，不做转义。
class MarkdownExporter {
  const MarkdownExporter();

  /// 可读导出只渲染未删除条目，条数与渲染结果一致。
  int visibleCount(List<Entry> entries) =>
      entries.where((entry) => entry.deletedAt == null).length;

  String render(List<Entry> entries, {DateTime? exportedAt}) {
    final stamp = (exportedAt ?? DateTime.now()).toUtc().toIso8601String();
    final sorted = [...entries]
      ..sort((a, b) {
        final byDay = b.dayKey.compareTo(a.dayKey);
        if (byDay != 0) return byDay;
        final byTime = b.createdAt.compareTo(a.createdAt);
        if (byTime != 0) return byTime;
        return b.id.compareTo(a.id);
      });
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('exportedAt: $stamp')
      ..writeln('entryCount: ${entries.length}')
      ..writeln('---')
      ..writeln()
      ..writeln('# 本地日记导出')
      ..writeln();
    String? currentDay;
    for (final entry in sorted) {
      if (entry.dayKey != currentDay) {
        currentDay = entry.dayKey;
        buffer
          ..writeln('## $currentDay')
          ..writeln();
      }
      final local = entry.createdAt.toLocal();
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      buffer
        ..writeln('**$hour:$minute**　${entry.content}')
        ..writeln();
    }
    return buffer.toString();
  }
}
