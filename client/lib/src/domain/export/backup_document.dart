import '../entry.dart';

/// 备份文件的格式标识，导入时用它判断文件是否属于本应用。
const String kBackupFormat = 'local-diary-backup';

/// 当前写出的备份格式版本。字段或结构变化时递增，旧版本仍应可导入。
const int kBackupVersion = 2;

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
