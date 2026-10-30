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

  /// 备份文件无法识别或已损坏时给用户看的原因。
  static const String damagedReason = '备份文件已损坏，无法恢复';

  /// 文件不是本应用的备份时给用户看的原因。
  static const String notOurBackupReason = '这不是本应用的备份文件';

  /// 备份来自比当前应用更新的版本时给用户看的原因。
  static const String newerVersionReason = '备份来自更新的版本，请先升级应用';

  /// 条目数据不完整、不能写进备份时给用户看的原因。
  static const String incompleteEntryReason = '有条记录数据不完整，无法导出';

  String encode(List<Entry> entries, {DateTime? exportedAt}) {
    final seenIds = <String>{};
    for (final entry in entries) {
      _validateEntry(entry);
      // 解码侧拒绝重复 ID，编码侧同样要拦住：
      // 否则会写出一份自家 decode 必然拒绝的备份。
      if (!seenIds.add(entry.id)) {
        throw const BackupFormatException(incompleteEntryReason);
      }
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
      throw const BackupFormatException(notOurBackupReason);
    } catch (_) {
      // 畸形 JSON 可能抛出非 FormatException，统一按损坏处理，
      // 保证界面总能映射到一句用户能看懂的话。
      throw const BackupFormatException(damagedReason);
    }
    if (raw is! Map<String, Object?> || raw['format'] != kBackupFormat) {
      throw const BackupFormatException(notOurBackupReason);
    }
    final version = raw['version'];
    if (version is! int) {
      throw const BackupFormatException(damagedReason);
    }
    if (version > kBackupVersion) {
      throw const BackupFormatException(newerVersionReason);
    }
    if (version < kMinBackupVersion) {
      throw const BackupFormatException(damagedReason);
    }
    final rawEntries = raw['entries'];
    if (rawEntries is! List) {
      throw const BackupFormatException(damagedReason);
    }
    final entryCount = raw['entryCount'];
    // 条数对不上说明文件被截断或改过，不接受这种备份。
    if (entryCount is! int || entryCount != rawEntries.length) {
      throw const BackupFormatException(damagedReason);
    }
    final entries = <Entry>[];
    final seenIds = <String>{};
    for (final item in rawEntries) {
      final entry = _decodeEntry(item);
      // 合法备份的 ID 是主键，不会重复；重复说明文件已损坏。
      if (!seenIds.add(entry.id)) {
        throw const BackupFormatException(damagedReason);
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
    final mood = entry.mood;
    // 只有已设心情的条目才写 mood，未设的不写键。
    if (mood != null) {
      map['mood'] = mood;
    }
    return map;
  }

  Entry _decodeEntry(Object? raw) {
    if (raw is! Map<String, Object?>) {
      throw const BackupFormatException(damagedReason);
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
      throw const BackupFormatException(damagedReason);
    }
    final rawDeletedAt = raw['deletedAt'];
    return Entry(
      id: id,
      content: content,
      createdAt: _parseDate(raw['createdAt']),
      updatedAt: _parseDate(raw['updatedAt']),
      dayKey: dayKey,
      deletedAt: rawDeletedAt == null ? null : _parseDate(rawDeletedAt),
      mood: raw['mood'] as String?,
    );
  }

  /// 编码前的校验，口径与解码侧一致：条目本身不合法就别写出去。
  void _validateEntry(Entry entry) {
    if (entry.id.isEmpty ||
        entry.content.trim().isEmpty ||
        !isValidDayKey(entry.dayKey)) {
      throw const BackupFormatException(incompleteEntryReason);
    }
  }

  /// 时间串必须带 `Z` 或显式时区偏移，否则同一份文件在不同设备会解出不同的绝对时刻。
  ///
  /// 判定只看解析结果的 `isUtc`：[DateTime.parse] 只要解析到时区部分
  /// （结尾的 `Z`，或偏移 `+08:00` / `+0800` / `+08`），返回的 [DateTime]
  /// 就一律是 `isUtc` 为 true 的 UTC 时刻（带非零偏移时按该偏移折算成 UTC）；
  /// 不带时区的时间串则按设备本地时区解析，`isUtc` 为 false。
  /// 因此 `!parsed.isUtc` 恰好就是「没带时区」的判据：带时区的一律接受，
  /// 不带时区的一律拒绝。
  DateTime _parseDate(Object? raw) {
    if (raw is! String) {
      throw const BackupFormatException(damagedReason);
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null || !parsed.isUtc) {
      throw const BackupFormatException(damagedReason);
    }
    return parsed.toUtc();
  }
}
