import 'dart:convert';

import '../entry.dart';
import 'backup_document.dart';

/// 备份数据无法编码，或备份文件无法识别、已损坏时抛出。
/// reason 是给用户看的中文原因。
class BackupFormatException implements Exception {
  const BackupFormatException(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// 备份文件与备份文档之间的转换。只做纯数据处理，不碰文件系统。
class BackupCodec {
  const BackupCodec();

  /// 时间串必须带时区标记，否则同一份文件在不同设备会解出不同的绝对时刻。
  static final RegExp _offsetPattern = RegExp(r'[+-]\d{2}:\d{2}$');

  String encode(List<Entry> entries, {DateTime? exportedAt}) {
    for (final entry in entries) {
      _validateEntry(entry);
    }
    final document = <String, Object?>{
      'format': kBackupFormat,
      'version': kBackupVersion,
      'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'entryCount': entries.length,
      'entries': [for (final entry in entries) _encodeEntry(entry)],
    };
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  BackupDocument decode(String text) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      throw const BackupFormatException('这不是本应用的备份文件');
    } catch (_) {
      // 畸形 JSON 可能抛出非 FormatException，统一按损坏处理，
      // 保证界面总能映射到一句用户能看懂的话。
      throw const BackupFormatException('备份文件已损坏，无法恢复');
    }
    if (raw is! Map<String, Object?> || raw['format'] != kBackupFormat) {
      throw const BackupFormatException('这不是本应用的备份文件');
    }
    final version = raw['version'];
    if (version is! int) {
      throw const BackupFormatException('备份文件已损坏，无法恢复');
    }
    if (version > kBackupVersion) {
      throw const BackupFormatException('备份来自更新的版本，请先升级应用');
    }
    if (version < kMinBackupVersion) {
      throw const BackupFormatException('备份文件已损坏，无法恢复');
    }
    final rawEntries = raw['entries'];
    if (rawEntries is! List) {
      throw const BackupFormatException('备份文件已损坏，无法恢复');
    }
    final entryCount = raw['entryCount'];
    // 条数对不上说明文件被截断或改过，不接受这种备份。
    if (entryCount is! int || entryCount != rawEntries.length) {
      throw const BackupFormatException('备份文件已损坏，无法恢复');
    }
    final entries = <Entry>[];
    final seenIds = <String>{};
    for (final item in rawEntries) {
      final entry = _decodeEntry(item);
      // 合法备份的 ID 是主键，不会重复；重复说明文件已损坏。
      if (!seenIds.add(entry.id)) {
        throw const BackupFormatException('备份文件已损坏，无法恢复');
      }
      entries.add(entry);
    }
    return BackupDocument(
      version: version,
      exportedAt: _parseDate(raw['exportedAt']),
      entries: entries,
    );
  }

  Map<String, Object?> _encodeEntry(Entry entry) {
    final map = <String, Object?>{
      'id': entry.id,
      'content': entry.content,
      'createdAt': entry.createdAt.toUtc().toIso8601String(),
      'updatedAt': entry.updatedAt.toUtc().toIso8601String(),
      'dayKey': entry.dayKey,
    };
    final deletedAt = entry.deletedAt;
    // 只有已删除的条目才写删除标记，v1 备份因此仍可被 v2 解码。
    if (deletedAt != null) {
      map['deletedAt'] = deletedAt.toUtc().toIso8601String();
    }
    return map;
  }

  Entry _decodeEntry(Object? raw) {
    if (raw is! Map<String, Object?>) {
      throw const BackupFormatException('备份文件已损坏，无法恢复');
    }
    final id = raw['id'];
    final content = raw['content'];
    final dayKey = raw['dayKey'];
    if (id is! String ||
        id.isEmpty ||
        content is! String ||
        content.trim().isEmpty ||
        dayKey is! String ||
        !isValidDayKey(dayKey)) {
      throw const BackupFormatException('备份文件已损坏，无法恢复');
    }
    final rawDeletedAt = raw['deletedAt'];
    return Entry(
      id: id,
      content: content,
      createdAt: _parseDate(raw['createdAt']),
      updatedAt: _parseDate(raw['updatedAt']),
      dayKey: dayKey,
      deletedAt: rawDeletedAt == null ? null : _parseDate(rawDeletedAt),
    );
  }

  /// 编码前的校验，口径与解码侧一致：条目本身不合法就别写出去。
  void _validateEntry(Entry entry) {
    if (entry.id.isEmpty ||
        entry.content.trim().isEmpty ||
        !isValidDayKey(entry.dayKey)) {
      throw const BackupFormatException('有条记录数据不完整，无法导出');
    }
  }

  DateTime _parseDate(Object? raw) {
    if (raw is! String) {
      throw const BackupFormatException('备份文件已损坏，无法恢复');
    }
    if (!raw.endsWith('Z') && !_offsetPattern.hasMatch(raw)) {
      throw const BackupFormatException('备份文件已损坏，无法恢复');
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw const BackupFormatException('备份文件已损坏，无法恢复');
    }
    return parsed.toUtc();
  }
}
