import '../entry.dart';

/// 备份文件的格式标识，导入时用它判断文件是否属于本应用。
const String kBackupFormat = 'local-diary-backup';

/// 备份格式版本。字段或结构变化时递增，旧版本仍应可导入。
const int kBackupVersion = 1;

/// 一份完整的备份。
class BackupDocument {
  const BackupDocument({
    required this.version,
    required this.exportedAt,
    required this.entries,
  });

  final int version;
  final DateTime exportedAt;
  final List<Entry> entries;
}
