import '../entry.dart';

/// 备份文件的格式标识，导入时用它判断文件是否属于本应用。
const String kBackupFormat = 'local-diary-backup';

/// 当前写出的备份格式版本。字段或结构变化时递增，旧版本仍应可导入。
///
/// v4（F010）新增条目 `photo` 字段（base64 字符串）；v3 旧备份无 photo，导入时视为空。
const int kBackupVersion = 4;

/// 仍可导入的最旧备份版本。
const int kMinBackupVersion = 1;

/// 一份完整的备份。
class BackupDocument {
  BackupDocument({
    required this.version,
    required this.exportedAt,
    required List<Entry> entries,
  }) : entries = List<Entry>.unmodifiable(entries);

  final int version;
  final DateTime exportedAt;

  /// 条目列表不可变：调用方不能绕过校验改坏已解码的备份。
  final List<Entry> entries;
}
