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
  });

  final String id;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String dayKey;
}

class EntryCursor {
  const EntryCursor(this.createdAt, this.id);
  final DateTime createdAt;
  final String id;
}
