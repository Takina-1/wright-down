import 'dart:convert';

import '../entry.dart';
import 'backup_document.dart';

/// 备份文件无法识别或已损坏时抛出，reason 是给用户看的中文原因。
class BackupFormatException implements Exception {
  const BackupFormatException(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// 备份文件与备份文档之间的转换。只做纯数据处理，不碰文件系统。
class BackupCodec {
  const BackupCodec();

  String encode(List<Entry> entries, {DateTime? exportedAt}) {
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
    final rawEntries = raw['entries'];
    if (rawEntries is! List) {
      throw const BackupFormatException('备份文件已损坏，无法恢复');
    }
    final entries = [for (final item in rawEntries) _decodeEntry(item)];
    final seenIds = <String>{};
    for (final entry in entries) {
      // 合法备份的 ID 是主键，不会重复；重复说明文件已损坏。
      if (!seenIds.add(entry.id)) {
        throw const BackupFormatException('备份文件已损坏，无法恢复');
      }
    }
    return BackupDocument(
      version: version,
      exportedAt: _parseDate(raw['exportedAt']),
      entries: entries,
    );
  }

  Map<String, Object?> _encodeEntry(Entry entry) => <String, Object?>{
    'id': entry.id,
    'content': entry.content,
    'createdAt': entry.createdAt.toUtc().toIso8601String(),
    'updatedAt': entry.updatedAt.toUtc().toIso8601String(),
    'dayKey': entry.dayKey,
  };

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
    return Entry(
      id: id,
      content: content,
      createdAt: _parseDate(raw['createdAt']),
      updatedAt: _parseDate(raw['updatedAt']),
      dayKey: dayKey,
    );
  }

  DateTime _parseDate(Object? raw) {
    if (raw is! String) {
      throw const BackupFormatException('备份文件已损坏，无法恢复');
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw const BackupFormatException('备份文件已损坏，无法恢复');
    }
    return parsed.toUtc();
  }
}
