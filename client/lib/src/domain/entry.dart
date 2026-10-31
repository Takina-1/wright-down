/// dayKey 必须是零填充的 ISO 日期，形如 2026-10-28。
///
/// 备份解码、导入与界面分组共用这一条规则，避免各处各写一份判断。
final RegExp dayKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// 判断 dayKey 是否是合法的本地日期键。
bool isValidDayKey(String value) => dayKeyPattern.hasMatch(value);

class Entry {
  const Entry({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.dayKey,
    this.deletedAt,
    this.mood,              // 可选；稳定标记字符串，非 emoji
    this.tags,              // 可选；已规范化（trim、去空、去重、保序）
  });

  final String id;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String dayKey;

  /// 删除时间。非空表示这条已被软删除：数据仍在库里，但不该出现在时间轴上。
  final DateTime? deletedAt;

  /// 心情标记。非空表示这条记录带心情。
  final String? mood;

  /// 标签列表。空列表表示无标签；不保证非空，构造时由调用方规范化。
  final List<String> tags;

  bool get isDeleted => deletedAt != null;
}

class EntryCursor {
  const EntryCursor(this.createdAt, this.id);
  final DateTime createdAt;
  final String id;
}
