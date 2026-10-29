# F004 导出与备份恢复 实现计划

> **执行要求：** 按任务顺序逐项执行，每项完成后单独提交。步骤用复选框跟踪。

**目标：** 让用户把日记导出为可恢复的 JSON 备份与可阅读的 Markdown 文件，并能把备份文件合并回本机。

**架构：** 编码与渲染是纯 Dart 函数，放在 `domain/export/`；文件选择、保存与分享封装在 `FileGateway` 接口之后，实现在 `platform/`；读写数据库走 `LocalEntryRepository` 新增的 `exportAll()` 与 `importAll()`；UI 只与控制器和仓储打交道，不直接触碰任何 SDK。

**技术栈：** Flutter 3.47.8 / Dart 3.13.7；sqflite 2.4.5；新增 file_selector 1.1.0（选文件）、file_picker 13.3.0（保存文件）、share_plus 13.3.1（系统分享）、path_provider 2.1.6（分享用临时目录）。

**需求来源：** [F004 导出与备份恢复](F004-导出与备份恢复-export-and-backup.md)

## 全局约束

- 备份与 Markdown 均为**明文**，不做加密与口令管理；界面必须写明这一点。
- 恢复采用**合并**：按条目 ID 比 `updatedAt`，备份较新才覆盖，本地较新一律跳过；重复导入同一备份必须幂等。
- 恢复要么全部成功，要么一条不写入：导入在单个事务内完成，失败整体回滚。
- 用户在文件选择器或分享面板取消时**不显示失败信息**，也不产生空文件、不残留临时文件。
- 备份格式固定 `format: "local-diary-backup"`、`version: 1`；`version` 高于当前支持时拒绝导入并提示升级。
- 时间在备份与数据库中统一使用 UTC ISO-8601 / epoch 毫秒；`dayKey` 保留写入当天的本地日期。
- Domain 层不得 import 任何框架或 SDK；`FileGateway` 接口只出现 `dart:typed_data`。
- Markdown 正文**不做转义**，换行与特殊字符原样输出。
- 文档与注释使用中文，与现有代码风格一致；不写「以后再说」式的空实现。

---

## 文件结构总览

**新建**

```text
client/lib/src/domain/export/backup_document.dart      备份文档模型与格式常量
client/lib/src/domain/export/backup_codec.dart         编解码与错误类型
client/lib/src/domain/export/markdown_exporter.dart    Markdown 渲染
client/lib/src/domain/export/restore_preview.dart      恢复预览与比较函数
client/lib/src/domain/export/import_summary.dart       恢复结果统计
client/lib/src/domain/export/file_gateway.dart         文件出入口抽象接口
client/lib/src/platform/saf_file_gateway.dart          SAF 实现（选文件、保存、分享）
client/lib/src/ui/export_controller.dart               导出与恢复的编排与状态
client/lib/src/ui/export_page.dart                     「导出与备份」二级页
client/test/domain/backup_codec_test.dart
client/test/domain/markdown_exporter_test.dart
client/test/domain/restore_preview_test.dart
client/test/data/sqlite_entry_import_test.dart
client/test/ui/export_controller_test.dart
client/test/ui/export_page_test.dart
```

**修改**

```text
client/pubspec.yaml                                   新增四个依赖
client/lib/src/domain/local_entry_repository.dart     新增 exportAll 与 importAll
client/lib/src/data/local/sqlite_entry_repository.dart 实现导出与合并导入
client/lib/src/ui/local_data_page.dart                新增入口并更新本地数据说明
client/lib/src/ui/home_page.dart                      把仓储传给「我的」页
client/test/support/memory_repository.dart            补齐新接口的实现
```

---

### Task 1：接入文件相关依赖

**文件：**
- 修改：`client/pubspec.yaml`
- 测试：无独立测试，用静态分析与后续构建验证

**接口：**
- 产出：`file_selector`、`file_picker`、`share_plus`、`path_provider` 四个依赖可用，后续任务才能 import。

- [ ] **Step 1：在 pubspec.yaml 的 dependencies 下增加四个依赖**

把 `client/pubspec.yaml` 的 dependencies 段改为：

```yaml
dependencies:
  file_picker: ^13.3.0
  file_selector: ^1.1.0
  flutter:
    sdk: flutter
  path: ^1.9.1
  path_provider: ^2.1.6
  share_plus: ^13.3.1
  sqflite: ^2.4.5
  sqflite_common: ^2.5.14
  uuid: ^4.6.0
```

版本约束来自 `https://pub.flutter-io.cn/api/packages/<包名>` 的 latest 版本，已确认满足本工程的 Dart `^3.13.7` 与 Flutter 3.47.8。

- [ ] **Step 2：拉取依赖**

```powershell
Set-Location D:\dev\myapp\client
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 pub get
```

预期：输出 `Got dependencies!`，无版本冲突。若 `cross_file` 出现冲突，说明某个插件要求 0.4.x 而另一个要求 0.3.x，此时按报错把冲突包的约束下调到报错提示的兼容版本，不要改工程 Dart SDK 约束。

- [ ] **Step 3：确认依赖树里四个包都在**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 pub deps --style=compact | Select-String "file_picker|file_selector|share_plus|path_provider"
```

预期：四行输出，各带版本号。

- [ ] **Step 4：静态分析仍然干净**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 analyze
```

预期：`No issues found!`

- [ ] **Step 5：提交**

```powershell
git add client/pubspec.yaml client/pubspec.lock
git commit -m "feat(F004): add file, picker and share dependencies"
```

---

### Task 2：备份文档模型与编解码

**文件：**
- 新建：`client/lib/src/domain/export/backup_document.dart`
- 新建：`client/lib/src/domain/export/backup_codec.dart`
- 测试：`client/test/domain/backup_codec_test.dart`

**接口：**
- 产出：
  - `const String kBackupFormat = 'local-diary-backup'`
  - `const int kBackupVersion = 1`
  - `class BackupDocument { final int version; final DateTime exportedAt; final List<Entry> entries; }`
  - `class BackupFormatException implements Exception { final String reason; }`
  - `class BackupCodec { const BackupCodec(); String encode(List<Entry> entries, {DateTime? exportedAt}); BackupDocument decode(String text); }`
- 依赖：无（只依赖既有的 `domain/entry.dart`）

- [ ] **Step 1：写失败的测试**

新建 `client/test/domain/backup_codec_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/backup_codec.dart';

void main() {
  const codec = BackupCodec();
  final created = DateTime.utc(2026, 10, 28, 8);
  Entry entry(String id, String content) => Entry(
    id: id,
    content: content,
    createdAt: created,
    updatedAt: created.add(const Duration(minutes: 5)),
    dayKey: '2026-10-28',
  );

  test('a decoded backup keeps every field of the original entry', () {
    final original = entry('a', '今天走了很远。\n明天继续 🌿');
    final text = codec.encode([original], exportedAt: created);
    final decoded = codec.decode(text);
    expect(decoded.version, 1);
    expect(decoded.exportedAt, created);
    expect(decoded.entries, hasLength(1));
    expect(decoded.entries.single.id, 'a');
    expect(decoded.entries.single.content, '今天走了很远。\n明天继续 🌿');
    expect(decoded.entries.single.createdAt, original.createdAt);
    expect(decoded.entries.single.updatedAt, original.updatedAt);
    expect(decoded.entries.single.dayKey, '2026-10-28');
  });

  test('an empty journal still encodes into a valid backup', () {
    final text = codec.encode(const [], exportedAt: created);
    final decoded = codec.decode(text);
    expect(decoded.entries, isEmpty);
    expect(text, contains('"entryCount": 0'));
  });

  test('a file that is not json is rejected as a foreign backup', () {
    expect(
      () => codec.decode('这不是 json'),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.reason,
          'reason',
          '这不是本应用的备份文件',
        ),
      ),
    );
  });

  test('a json file from another app is rejected', () {
    expect(
      () => codec.decode('{"format":"other-app","version":1,"entries":[]}'),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.reason,
          'reason',
          '这不是本应用的备份文件',
        ),
      ),
    );
  });

  test('a newer backup version asks the user to update the app', () {
    expect(
      () => codec.decode('{"format":"local-diary-backup","version":2,"entries":[]}'),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.reason,
          'reason',
          '备份来自更新的版本，请先升级应用',
        ),
      ),
    );
  });

  test('an entry with a missing field is reported as damaged', () {
    const broken = '{"format":"local-diary-backup","version":1,'
        '"entries":[{"id":"a","content":"正文"}]}';
    expect(
      () => codec.decode(broken),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.reason,
          'reason',
          '备份文件已损坏，无法恢复',
        ),
      ),
    );
  });

  test('an entry with a wrong field type is reported as damaged', () {
    const broken = '{"format":"local-diary-backup","version":1,'
        '"entries":[{"id":"a","content":42,"createdAt":"2026-10-28T08:00:00.000Z",'
        '"updatedAt":"2026-10-28T08:00:00.000Z","dayKey":"2026-10-28"}]}';
    expect(
      () => codec.decode(broken),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.reason,
          'reason',
          '备份文件已损坏，无法恢复',
        ),
      ),
    );
  });
}
```

- [ ] **Step 2：运行测试确认失败**

```powershell
Set-Location D:\dev\myapp\client
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test test/domain/backup_codec_test.dart
```

预期：编译失败，提示 `BackupCodec` / `BackupDocument` 未定义。

- [ ] **Step 3：写备份文档模型**

新建 `client/lib/src/domain/export/backup_document.dart`：

```dart
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
```

- [ ] **Step 4：写编解码实现**

新建 `client/lib/src/domain/export/backup_codec.dart`：

```dart
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
    if (raw is! Map<String, Object?> ||
        raw['format'] != kBackupFormat) {
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
    final ids = {for (final entry in entries) entry.id};
    if (ids.length != entries.length) {
      throw const BackupFormatException('备份文件已损坏，无法恢复');
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
    if (id is! String || id.isEmpty ||
        content is! String ||
        dayKey is! String || dayKey.isEmpty) {
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
```

- [ ] **Step 5：运行测试确认通过**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test test/domain/backup_codec_test.dart
```

预期：7 项全部通过。

- [ ] **Step 6：提交**

```powershell
git add client/lib/src/domain/export client/test/domain/backup_codec_test.dart
git commit -m "feat(F004): encode and decode backup documents"
```

---

### Task 3：Markdown 导出

**文件：**
- 新建：`client/lib/src/domain/export/markdown_exporter.dart`
- 测试：`client/test/domain/markdown_exporter_test.dart`

**接口：**
- 产出：`class MarkdownExporter { const MarkdownExporter(); String render(List<Entry> entries, {DateTime? exportedAt}); }`
- 依赖：Task 2 无耦合，可与 Task 2 并行，但共用 `domain/entry.dart`

- [ ] **Step 1：写失败的测试**

新建 `client/test/domain/markdown_exporter_test.dart`：

```dart
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
        entry('c', '第二天的一条', createdAt: DateTime(2026, 10, 29, 7, 0)),
      ],
      exportedAt: DateTime.utc(2026, 10, 29, 4),
    );
    expect(markdown.indexOf('第二天的一条') < markdown.indexOf('较晚的一条'), isTrue);
    expect(markdown.indexOf('较晚的一条') < markdown.indexOf('较早的一条'), isTrue);
    expect(markdown.indexOf('## 2026-10-29') < markdown.indexOf('## 2026-10-28'), isTrue);
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
```

- [ ] **Step 2：运行测试确认失败**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test test/domain/markdown_exporter_test.dart
```

预期：编译失败，提示 `MarkdownExporter` 未定义。

- [ ] **Step 3：写实现**

新建 `client/lib/src/domain/export/markdown_exporter.dart`：

```dart
import '../entry.dart';

/// 把条目渲染成可阅读的 Markdown。正文原样输出，不做转义。
class MarkdownExporter {
  const MarkdownExporter();

  String render(List<Entry> entries, {DateTime? exportedAt}) {
    final stamp = (exportedAt ?? DateTime.now()).toUtc().toIso8601String();
    final sorted = [...entries]..sort((a, b) {
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
```

- [ ] **Step 4：运行测试确认通过**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test test/domain/markdown_exporter_test.dart
```

预期：5 项全部通过。

- [ ] **Step 5：提交**

```powershell
git add client/lib/src/domain/export/markdown_exporter.dart client/test/domain/markdown_exporter_test.dart
git commit -m "feat(F004): render entries as markdown"
```

---

### Task 4：恢复预览的纯函数比较

**文件：**
- 新建：`client/lib/src/domain/export/restore_preview.dart`
- 测试：`client/test/domain/restore_preview_test.dart`

**接口：**
- 产出：
  - `class RestorePreview { final int total; final int inserted; final int updated; final int skipped; }`
  - `RestorePreview compareRestore(List<Entry> local, List<Entry> incoming)`
- 依赖：无

- [ ] **Step 1：写失败的测试**

新建 `client/test/domain/restore_preview_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/restore_preview.dart';

void main() {
  final base = DateTime.utc(2026, 10, 28, 8);
  Entry entry(String id, {DateTime? updatedAt, String content = '正文'}) => Entry(
    id: id,
    content: content,
    createdAt: base,
    updatedAt: updatedAt ?? base,
    dayKey: '2026-10-28',
  );

  test('a new id is counted as an insertion', () {
    final preview = compareRestore(const [], [entry('a')]);
    expect(preview.inserted, 1);
    expect(preview.updated, 0);
    expect(preview.skipped, 0);
    expect(preview.total, 1);
  });

  test('a newer backup entry is counted as an update', () {
    final preview = compareRestore(
      [entry('a', updatedAt: base)],
      [entry('a', updatedAt: base.add(const Duration(minutes: 1)))],
    );
    expect(preview.updated, 1);
    expect(preview.skipped, 0);
  });

  test('an older backup entry is counted as skipped', () {
    final preview = compareRestore(
      [entry('a', updatedAt: base.add(const Duration(minutes: 1)))],
      [entry('a', updatedAt: base)],
    );
    expect(preview.skipped, 1);
    expect(preview.updated, 0);
  });

  test('an identical entry is counted as skipped', () {
    final preview = compareRestore([entry('a')], [entry('a')]);
    expect(preview.skipped, 1);
  });
}
```

- [ ] **Step 2：运行测试确认失败**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test test/domain/restore_preview_test.dart
```

预期：编译失败，提示 `compareRestore` 未定义。

- [ ] **Step 3：写实现**

新建 `client/lib/src/domain/export/restore_preview.dart`：

```dart
import '../entry.dart';

/// 导入前给用户看的合并结果预告。
class RestorePreview {
  const RestorePreview({
    required this.total,
    required this.inserted,
    required this.updated,
    required this.skipped,
  });

  final int total;
  final int inserted;
  final int updated;
  final int skipped;
}

/// 按 ID 与修改时间比较本地和备份，给出这次恢复会改动什么。
/// 判断规则与仓储层的合并规则保持一致。
RestorePreview compareRestore(List<Entry> local, List<Entry> incoming) {
  final byId = {for (final entry in local) entry.id: entry};
  var inserted = 0;
  var updated = 0;
  var skipped = 0;
  for (final entry in incoming) {
    final existing = byId[entry.id];
    if (existing == null) {
      inserted++;
    } else if (entry.updatedAt.millisecondsSinceEpoch >
        existing.updatedAt.millisecondsSinceEpoch) {
      updated++;
    } else {
      skipped++;
    }
  }
  return RestorePreview(
    total: incoming.length,
    inserted: inserted,
    updated: updated,
    skipped: skipped,
  );
}
```

- [ ] **Step 4：运行测试确认通过**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test test/domain/restore_preview_test.dart
```

预期：4 项全部通过。

- [ ] **Step 5：提交**

```powershell
git add client/lib/src/domain/export/restore_preview.dart client/test/domain/restore_preview_test.dart
git commit -m "feat(F004): preview what a restore would change"
```

---

### Task 5：仓储的全量导出与合并导入

**文件：**
- 新建：`client/lib/src/domain/export/import_summary.dart`
- 修改：`client/lib/src/domain/local_entry_repository.dart`
- 修改：`client/lib/src/data/local/sqlite_entry_repository.dart`
- 修改：`client/test/support/memory_repository.dart`
- 测试：`client/test/data/sqlite_entry_import_test.dart`

**接口：**
- 产出：
  - `class ImportSummary { final int inserted; final int updated; final int skipped; int get total; }`
  - `LocalEntryRepository.exportAll()` → `Future<List<Entry>>`，按创建时间倒序返回全部条目
  - `LocalEntryRepository.importAll(List<Entry> entries)` → `Future<ImportSummary>`，单事务合并
- 依赖：无（只用到既有的 `Entry`）

- [ ] **Step 1：写失败的测试**

新建 `client/test/data/sqlite_entry_import_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late SqliteEntryRepository repo;
  final time = DateTime.utc(2026, 10, 28, 8);

  Entry entry(
    String id,
    String content, {
    DateTime? createdAt,
    DateTime? updatedAt,
    String dayKey = '2026-10-28',
  }) => Entry(
    id: id,
    content: content,
    createdAt: createdAt ?? time,
    updatedAt: updatedAt ?? time,
    dayKey: dayKey,
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('local_diary_import_');
    repo = SqliteEntryRepository(
      factory: databaseFactoryFfi,
      path: '${temp.path}/journal.db',
    );
  });
  tearDown(() async {
    await repo.close();
    await temp.delete(recursive: true);
  });

  test('exportAll returns every entry, not only the first page', () async {
    for (var i = 0; i < 40; i++) {
      await repo.save(entry('id-${i.toString().padLeft(2, '0')}', '第 $i 条'));
    }
    final exported = await repo.exportAll();
    expect(exported, hasLength(40));
    expect(exported.first.id, 'id-39');
    expect(exported.last.id, 'id-00');
  });

  test('a new id from a backup is inserted', () async {
    final summary = await repo.importAll([entry('a', '来自备份')]);
    expect(summary.inserted, 1);
    expect(summary.updated, 0);
    expect(summary.skipped, 0);
    expect((await repo.list()).single.content, '来自备份');
  });

  test('a newer backup entry updates content but keeps creation time', () async {
    await repo.save(entry('a', '本机内容', createdAt: time));
    final summary = await repo.importAll([
      entry(
        'a',
        '备份内容',
        createdAt: time.add(const Duration(days: 1)),
        updatedAt: time.add(const Duration(minutes: 1)),
      ),
    ]);
    expect(summary.updated, 1);
    final stored = (await repo.list()).single;
    expect(stored.content, '备份内容');
    expect(stored.createdAt, time);
    expect(stored.dayKey, '2026-10-28');
  });

  test('an older backup entry never overwrites a newer local entry', () async {
    await repo.save(
      entry('a', '本机较新', updatedAt: time.add(const Duration(minutes: 10))),
    );
    final summary = await repo.importAll([
      entry('a', '备份较旧', updatedAt: time),
    ]);
    expect(summary.skipped, 1);
    expect((await repo.list()).single.content, '本机较新');
  });

  test('importing the same backup twice changes nothing the second time', () async {
    final backup = [
      entry('a', '第一条', updatedAt: time.add(const Duration(minutes: 1))),
      entry('b', '第二条', updatedAt: time.add(const Duration(minutes: 2))),
    ];
    final first = await repo.importAll(backup);
    expect(first.inserted, 2);
    final second = await repo.importAll(backup);
    expect(second.inserted, 0);
    expect(second.updated, 0);
    expect(second.skipped, 2);
    expect(await repo.list(), hasLength(2));
  });

  test('a broken entry rolls the whole import back', () async {
    await repo.save(entry('keep', '保留这条'));
    await expectLater(
      repo.importAll([
        entry('new', '会被回滚'),
        entry('', '缺少 ID'),
      ]),
      throwsArgumentError,
    );
    final stored = await repo.list();
    expect(stored, hasLength(1));
    expect(stored.single.id, 'keep');
  });
}
```

- [ ] **Step 2：运行测试确认失败**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test test/data/sqlite_entry_import_test.dart
```

预期：编译失败，提示 `exportAll` 与 `importAll` 未定义。

- [ ] **Step 3：写结果统计模型**

新建 `client/lib/src/domain/export/import_summary.dart`：

```dart
/// 一次恢复实际改动条目的统计。
class ImportSummary {
  const ImportSummary({
    required this.inserted,
    required this.updated,
    required this.skipped,
  });

  final int inserted;
  final int updated;
  final int skipped;

  int get total => inserted + updated + skipped;
}
```

- [ ] **Step 4：扩展仓储接口**

把 `client/lib/src/domain/local_entry_repository.dart` 改为：

```dart
import 'entry.dart';
import 'export/import_summary.dart';

abstract interface class LocalEntryRepository {
  Future<void> save(Entry entry);
  Future<List<Entry>> list({EntryCursor? before, int limit = 30});

  /// 导出用：一次取出全部条目，按创建时间倒序排列，不受分页限制。
  Future<List<Entry>> exportAll();

  /// 恢复用：按条目 ID 合并导入。备份较新才覆盖，本地较新一律跳过。
  /// 整个导入在一个事务内完成，失败时整体回滚。
  Future<ImportSummary> importAll(List<Entry> entries);

  Future<void> close();
}
```

- [ ] **Step 5：实现 SQLite 导出与合并导入**

修改 `client/lib/src/data/local/sqlite_entry_repository.dart`。先在文件顶部的 import 区加入：

```dart
import '../../domain/export/import_summary.dart';
```

再把 `list` 方法里的行映射提取成共用方法，并在类中加入两个新方法。改完后整个文件为：

```dart
import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/entry.dart';
import '../../domain/export/import_summary.dart';
import '../../domain/local_entry_repository.dart';

class SqliteEntryRepository implements LocalEntryRepository {
  SqliteEntryRepository({required this.factory, required this.path});
  final DatabaseFactory factory;
  final String path;
  Future<Database>? _databaseFuture;

  Future<Database> _database() async {
    try {
      return await (_databaseFuture ??= factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) async {
            await db.rawQuery('PRAGMA journal_mode = WAL');
            await db.execute('PRAGMA busy_timeout = 5000');
          },
          onCreate: (db, version) async {
            await db.execute('''CREATE TABLE entries (
              id TEXT PRIMARY KEY NOT NULL,
              content TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              day_key TEXT NOT NULL
            )''');
            await db.execute(
              'CREATE INDEX entries_timeline ON entries(created_at DESC, id DESC)',
            );
            await db.execute('CREATE INDEX entries_day ON entries(day_key)');
          },
        ),
      ));
    } catch (_) {
      _databaseFuture = null;
      rethrow;
    }
  }

  @override
  Future<void> save(Entry entry) async {
    if (entry.id.isEmpty || entry.content.trim().isEmpty) {
      throw ArgumentError('An entry needs an id and non-empty content');
    }
    final db = await _database();
    await db.transaction((txn) async {
      final updated = await txn.update(
        'entries',
        {
          'content': entry.content,
          'updated_at': entry.updatedAt.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [entry.id],
      );
      if (updated == 0) {
        await txn.insert('entries', {
          'id': entry.id,
          'content': entry.content,
          'created_at': entry.createdAt.millisecondsSinceEpoch,
          'updated_at': entry.updatedAt.millisecondsSinceEpoch,
          'day_key': entry.dayKey,
        });
      }
    });
  }

  @override
  Future<List<Entry>> list({EntryCursor? before, int limit = 30}) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    final db = await _database();
    final rows = await db.query(
      'entries',
      where: before == null
          ? null
          : '(created_at < ? OR (created_at = ? AND id < ?))',
      whereArgs: before == null
          ? null
          : [
              before.createdAt.millisecondsSinceEpoch,
              before.createdAt.millisecondsSinceEpoch,
              before.id,
            ],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(_toEntry).toList();
  }

  @override
  Future<List<Entry>> exportAll() async {
    final db = await _database();
    final rows = await db.query('entries', orderBy: 'created_at DESC, id DESC');
    return rows.map(_toEntry).toList();
  }

  @override
  Future<ImportSummary> importAll(List<Entry> entries) async {
    final db = await _database();
    var inserted = 0;
    var updated = 0;
    var skipped = 0;
    await db.transaction((txn) async {
      for (final entry in entries) {
        if (entry.id.isEmpty) {
          throw ArgumentError('An imported entry needs an id');
        }
        final rows = await txn.query(
          'entries',
          columns: ['updated_at'],
          where: 'id = ?',
          whereArgs: [entry.id],
          limit: 1,
        );
        if (rows.isEmpty) {
          await txn.insert('entries', {
            'id': entry.id,
            'content': entry.content,
            'created_at': entry.createdAt.millisecondsSinceEpoch,
            'updated_at': entry.updatedAt.millisecondsSinceEpoch,
            'day_key': entry.dayKey,
          });
          inserted++;
          continue;
        }
        final localUpdatedAt = rows.first['updated_at'] as int;
        if (entry.updatedAt.millisecondsSinceEpoch > localUpdatedAt) {
          await txn.update(
            'entries',
            {
              'content': entry.content,
              'updated_at': entry.updatedAt.millisecondsSinceEpoch,
            },
            where: 'id = ?',
            whereArgs: [entry.id],
          );
          updated++;
        } else {
          skipped++;
        }
      }
    });
    return ImportSummary(
      inserted: inserted,
      updated: updated,
      skipped: skipped,
    );
  }

  Entry _toEntry(Map<String, Object?> row) => Entry(
    id: row['id'] as String,
    content: row['content'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row['created_at'] as int,
      isUtc: true,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      row['updated_at'] as int,
      isUtc: true,
    ),
    dayKey: row['day_key'] as String,
  );

  @override
  Future<void> close() async {
    final pending = _databaseFuture;
    _databaseFuture = null;
    if (pending != null) await (await pending).close();
  }
}
```

- [ ] **Step 6：补齐内存仓储**

修改 `client/test/support/memory_repository.dart`，在 import 区加入：

```dart
import 'package:local_diary/src/domain/export/import_summary.dart';
```

并在 `list` 方法之后加入：

```dart
  @override
  Future<List<Entry>> exportAll() async {
    final sorted = entries.values.toList()
      ..sort((a, b) {
        final time = b.createdAt.compareTo(a.createdAt);
        return time == 0 ? b.id.compareTo(a.id) : time;
      });
    return sorted;
  }

  @override
  Future<ImportSummary> importAll(List<Entry> incoming) async {
    var inserted = 0;
    var updated = 0;
    var skipped = 0;
    for (final entry in incoming) {
      final existing = entries[entry.id];
      if (existing == null) {
        entries[entry.id] = entry;
        inserted++;
      } else if (entry.updatedAt.millisecondsSinceEpoch >
          existing.updatedAt.millisecondsSinceEpoch) {
        entries[entry.id] = Entry(
          id: existing.id,
          content: entry.content,
          createdAt: existing.createdAt,
          updatedAt: entry.updatedAt,
          dayKey: existing.dayKey,
        );
        updated++;
      } else {
        skipped++;
      }
    }
    return ImportSummary(
      inserted: inserted,
      updated: updated,
      skipped: skipped,
    );
  }
```

- [ ] **Step 7：运行测试确认通过**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test test/data/sqlite_entry_import_test.dart test/data/sqlite_entry_repository_test.dart
```

预期：新增 6 项与原有 4 项全部通过。

- [ ] **Step 8：提交**

```powershell
git add client/lib/src/domain client/lib/src/data/local client/test
git commit -m "feat(F004): export all entries and merge backups"
```

---

### Task 6：文件出入口接口与 Android 实现

**文件：**
- 新建：`client/lib/src/domain/export/file_gateway.dart`
- 新建：`client/lib/src/platform/saf_file_gateway.dart`
- 测试：本任务只有真机可验证，宿主无测试；依赖在 Task 8 用静态分析与 APK 构建把关

**接口：**
- 产出：`abstract interface class FileGateway`，三个方法：
  - `Future<String?> saveFile({required String suggestedName, required Uint8List bytes, required String mimeType})`——用户取消返回 null
  - `Future<Uint8List?> pickFile({required String mimeType, required List<String> extensions})`——用户取消返回 null
  - `Future<void> shareFile({required String fileName, required Uint8List bytes, required String mimeType})`
- 依赖：Task 1 的四个依赖

- [ ] **Step 1：写抽象接口**

新建 `client/lib/src/domain/export/file_gateway.dart`：

```dart
import 'dart:typed_data';

/// 文件的出入口。实现放在 platform 层，domain 不依赖任何 SDK。
abstract interface class FileGateway {
  /// 让用户选择保存位置并写入内容，返回保存位置；用户取消时返回 null。
  Future<String?> saveFile({
    required String suggestedName,
    required Uint8List bytes,
    required String mimeType,
  });

  /// 让用户选择一个文件并读出内容；用户取消时返回 null。
  Future<Uint8List?> pickFile({
    required String mimeType,
    required List<String> extensions,
  });

  /// 把内容写进临时文件并交给系统分享面板。
  Future<void> shareFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  });
}
```

- [ ] **Step 2：写 Android 实现**

新建 `client/lib/src/platform/saf_file_gateway.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/export/file_gateway.dart';

/// 基于系统文件选择器与分享面板的实现。
///
/// 选文件用 file_selector：Android 上它会把内容读进内存，返回的 XFile 可以直接读。
/// 保存用 file_picker：file_selector 在 Android 上没有实现保存接口。
/// 分享先把内容写进临时目录，再交给系统分享面板。
class SafFileGateway implements FileGateway {
  const SafFileGateway();

  @override
  Future<String?> saveFile({
    required String suggestedName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: suggestedName,
      bytes: bytes,
      mimeType: mimeType,
    );
    return uri?.toString();
  }

  @override
  Future<Uint8List?> pickFile({
    required String mimeType,
    required List<String> extensions,
  }) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: '本地日记备份',
          extensions: extensions,
          mimeTypes: [mimeType],
        ),
      ],
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> shareFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final directory = await getTemporaryDirectory();
    final target = File(path.join(directory.path, fileName));
    await target.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(target.path, mimeType: mimeType)],
        title: fileName,
      ),
    );
  }
}
```

- [ ] **Step 3：静态分析**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 analyze
```

预期：`No issues found!`。若 `FilePicker.saveFile` 报参数错误，说明 file_picker 版本的静态方法签名不同，按报错提示补齐参数（该版本的 `type` 与 `allowedExtensions` 已废弃，无需传入）。

- [ ] **Step 4：提交**

```powershell
git add client/lib/src/domain/export/file_gateway.dart client/lib/src/platform/saf_file_gateway.dart
git commit -m "feat(F004): add file gateway for saving, picking and sharing"
```

---

### Task 7：导出与恢复的控制器

**文件：**
- 新建：`client/lib/src/ui/export_controller.dart`
- 测试：`client/test/ui/export_controller_test.dart`

**接口：**
- 产出：
  - `enum ExportStatus { idle, working, success, failure }`
  - `class ExportController extends ChangeNotifier`
    - `ExportStatus get status`
    - `String? get message`（成功或失败的提示文案）
    - `bool get canShare`（是否刚导出过可分享的文件）
    - `Future<bool> exportBackup()`
    - `Future<bool> exportMarkdown()`
    - `Future<bool> shareLastExport()`
    - `Future<RestorePreview?> pickBackup()`
    - `Future<ImportSummary?> confirmRestore(BackupDocument document)`
- 依赖：Task 2 的 `BackupCodec`、Task 3 的 `MarkdownExporter`、Task 4 的 `compareRestore`、Task 5 的 `LocalEntryRepository`、Task 6 的 `FileGateway`

- [ ] **Step 1：写失败的测试**

新建 `client/test/ui/export_controller_test.dart`：

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/backup_codec.dart';
import 'package:local_diary/src/domain/export/file_gateway.dart';
import 'package:local_diary/src/ui/export_controller.dart';

import '../support/memory_repository.dart';

class FakeFileGateway implements FileGateway {
  String? savedName;
  Uint8List? savedBytes;
  bool cancelSave = false;
  bool cancelPick = false;
  Uint8List? pickResult;
  String? sharedName;

  @override
  Future<String?> saveFile({
    required String suggestedName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    if (cancelSave) return null;
    savedName = suggestedName;
    savedBytes = bytes;
    return 'content://fake/$suggestedName';
  }

  @override
  Future<Uint8List?> pickFile({
    required String mimeType,
    required List<String> extensions,
  }) async {
    if (cancelPick) return null;
    return pickResult;
  }

  @override
  Future<void> shareFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    sharedName = fileName;
  }
}

void main() {
  final time = DateTime.utc(2026, 10, 28, 8);
  Entry entry(String id, String content, {DateTime? updatedAt}) => Entry(
    id: id,
    content: content,
    createdAt: time,
    updatedAt: updatedAt ?? time,
    dayKey: '2026-10-28',
  );

  test('exporting a backup writes every entry and reports the count', () async {
    final repo = MemoryRepository();
    repo.entries['a'] = entry('a', '第一条');
    repo.entries['b'] = entry('b', '第二条');
    final gateway = FakeFileGateway();
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final ok = await controller.exportBackup();

    expect(ok, isTrue);
    expect(controller.status, ExportStatus.success);
    expect(controller.message, '已导出 2 条');
    expect(gateway.savedName, endsWith('.json'));
    final document = const BackupCodec().decode(
      utf8.decode(gateway.savedBytes!),
    );
    expect(document.entries, hasLength(2));
  });

  test('cancelling the save dialog is not reported as a failure', () async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway()..cancelSave = true;
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final ok = await controller.exportBackup();

    expect(ok, isFalse);
    expect(controller.status, ExportStatus.idle);
    expect(controller.message, isNull);
  });

  test('a markdown export is offered for sharing after it is saved', () async {
    final repo = MemoryRepository();
    repo.entries['a'] = entry('a', '第一条');
    final gateway = FakeFileGateway();
    final controller = ExportController(repository: repo, fileGateway: gateway);

    await controller.exportMarkdown();

    expect(gateway.savedName, endsWith('.md'));
    expect(controller.canShare, isTrue);
    await controller.shareLastExport();
    expect(gateway.sharedName, endsWith('.md'));
  });

  test('picking a broken backup explains the reason and imports nothing', () async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(utf8.encode('不是备份'));
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final preview = await controller.pickBackup();

    expect(preview, isNull);
    expect(controller.status, ExportStatus.failure);
    expect(controller.message, '这不是本应用的备份文件');
    expect(repo.entries, isEmpty);
  });

  test('cancelling the file picker is not reported as a failure', () async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway()..cancelPick = true;
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final preview = await controller.pickBackup();

    expect(preview, isNull);
    expect(controller.status, ExportStatus.idle);
    expect(controller.message, isNull);
  });

  test('a picked backup is previewed before it is restored', () async {
    final repo = MemoryRepository();
    repo.entries['a'] = entry('a', '本机内容');
    final backup = const BackupCodec().encode(
      [
        entry('a', '备份较新', updatedAt: time.add(const Duration(minutes: 5))),
        entry('b', '备份新增'),
      ],
      exportedAt: time,
    );
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(utf8.encode(backup));
    final controller = ExportController(repository: repo, fileGateway: gateway);

    final preview = await controller.pickBackup();

    expect(preview, isNotNull);
    expect(preview!.total, 2);
    expect(preview.inserted, 1);
    expect(preview.updated, 1);
    expect(repo.entries['a']!.content, '本机内容');
  });

  test('confirming a restore merges the backup into the journal', () async {
    final repo = MemoryRepository();
    final backup = const BackupCodec().encode(
      [entry('b', '备份新增')],
      exportedAt: time,
    );
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(utf8.encode(backup));
    final controller = ExportController(repository: repo, fileGateway: gateway);

    await controller.pickBackup();
    final document = const BackupCodec().decode(
      utf8.decode(gateway.pickResult!),
    );
    final summary = await controller.confirmRestore(document);

    expect(summary, isNotNull);
    expect(summary!.inserted, 1);
    expect(repo.entries['b']!.content, '备份新增');
    expect(controller.message, '恢复完成：新增 1 条，更新 0 条，跳过 0 条');
  });
}
```

- [ ] **Step 2：运行测试确认失败**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test test/ui/export_controller_test.dart
```

预期：编译失败，提示 `ExportController` 未定义。

- [ ] **Step 3：写控制器**

新建 `client/lib/src/ui/export_controller.dart`：

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../domain/entry.dart';
import '../domain/export/backup_codec.dart';
import '../domain/export/backup_document.dart';
import '../domain/export/file_gateway.dart';
import '../domain/export/import_summary.dart';
import '../domain/export/markdown_exporter.dart';
import '../domain/export/restore_preview.dart';
import '../domain/local_entry_repository.dart';

enum ExportStatus { idle, working, success, failure }

/// 导出与恢复的编排：读条目、编码、交给文件出口，并管理界面要显示的状态。
class ExportController extends ChangeNotifier {
  ExportController({
    required this.repository,
    required this.fileGateway,
    BackupCodec codec = const BackupCodec(),
    MarkdownExporter markdownExporter = const MarkdownExporter(),
    DateTime Function()? now,
  })  : _codec = codec,
        _markdownExporter = markdownExporter,
        _now = now ?? DateTime.now;

  final LocalEntryRepository repository;
  final FileGateway fileGateway;
  final BackupCodec _codec;
  final MarkdownExporter _markdownExporter;
  final DateTime Function() _now;

  ExportStatus _status = ExportStatus.idle;
  String? _message;
  Uint8List? _lastExportBytes;
  String? _lastExportName;
  BackupDocument? _pendingDocument;

  ExportStatus get status => _status;
  String? get message => _message;
  bool get canShare => _lastExportBytes != null;

  /// 最近一次选中、等待用户确认的备份文件。
  BackupDocument? get pendingDocument => _pendingDocument;

  Future<bool> exportBackup() => _export(
    extension: 'json',
    mimeType: 'application/json',
    encode: (entries) => _codec.encode(entries, exportedAt: _now()),
  );

  Future<bool> exportMarkdown() => _export(
    extension: 'md',
    mimeType: 'text/markdown',
    encode: (entries) => _markdownExporter.render(entries, exportedAt: _now()),
  );

  Future<bool> _export({
    required String extension,
    required String mimeType,
    required String Function(List<Entry> entries) encode,
  }) async {
    _status = ExportStatus.working;
    _message = null;
    notifyListeners();
    try {
      final entries = await repository.exportAll();
      final bytes = Uint8List.fromList(utf8.encode(encode(entries)));
      final name = '本地日记-${_stamp()}.$extension';
      final saved = await fileGateway.saveFile(
        suggestedName: name,
        bytes: bytes,
        mimeType: mimeType,
      );
      if (saved == null) {
        _status = ExportStatus.idle;
        notifyListeners();
        return false;
      }
      _lastExportBytes = bytes;
      _lastExportName = name;
      _status = ExportStatus.success;
      _message = '已导出 ${entries.length} 条';
      notifyListeners();
      return true;
    } catch (_) {
      _status = ExportStatus.failure;
      _message = '导出失败，请检查存储空间后重试';
      notifyListeners();
      return false;
    }
  }

  Future<bool> shareLastExport() async {
    final bytes = _lastExportBytes;
    final name = _lastExportName;
    if (bytes == null || name == null) return false;
    _status = ExportStatus.working;
    notifyListeners();
    try {
      await fileGateway.shareFile(
        fileName: name,
        bytes: bytes,
        mimeType: name.endsWith('.md') ? 'text/markdown' : 'application/json',
      );
      _status = ExportStatus.success;
      _message = '已打开分享面板';
      notifyListeners();
      return true;
    } catch (_) {
      _status = ExportStatus.failure;
      _message = '分享失败，请重试';
      notifyListeners();
      return false;
    }
  }

  Future<RestorePreview?> pickBackup() async {
    _status = ExportStatus.working;
    _message = null;
    notifyListeners();
    try {
      final bytes = await fileGateway.pickFile(
        mimeType: 'application/json',
        extensions: ['json'],
      );
      if (bytes == null) {
        _status = ExportStatus.idle;
        notifyListeners();
        return null;
      }
      final document = _codec.decode(utf8.decode(bytes));
      final local = await repository.exportAll();
      final preview = compareRestore(local, document.entries);
      _pendingDocument = document;
      _status = ExportStatus.success;
      _message = '已选择备份文件';
      notifyListeners();
      return preview;
    } on BackupFormatException catch (error) {
      _status = ExportStatus.failure;
      _message = error.reason;
      notifyListeners();
      return null;
    } catch (_) {
      _status = ExportStatus.failure;
      _message = '无法读取所选文件';
      notifyListeners();
      return null;
    }
  }

  Future<ImportSummary?> confirmRestore(BackupDocument document) async {
    _status = ExportStatus.working;
    _message = null;
    notifyListeners();
    try {
      final summary = await repository.importAll(document.entries);
      _status = ExportStatus.success;
      _message =
          '恢复完成：新增 ${summary.inserted} 条，更新 ${summary.updated} 条，跳过 ${summary.skipped} 条';
      notifyListeners();
      return summary;
    } catch (_) {
      _status = ExportStatus.failure;
      _message = '恢复失败，未导入任何条目';
      notifyListeners();
      return null;
    }
  }

  String _stamp() {
    final local = _now().toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day-$hour$minute';
  }
}
```

- [ ] **Step 4：运行测试确认通过**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test test/ui/export_controller_test.dart
```

预期：7 项全部通过。

- [ ] **Step 5：提交**

```powershell
git add client/lib/src/ui/export_controller.dart client/test/ui/export_controller_test.dart
git commit -m "feat(F004): orchestrate export and restore actions"
```

---

### Task 8：导出页面与「我的」入口

**文件：**
- 新建：`client/lib/src/ui/export_page.dart`
- 修改：`client/lib/src/ui/local_data_page.dart`
- 修改：`client/lib/src/ui/home_page.dart`
- 测试：`client/test/ui/export_page_test.dart`

**接口：**
- 产出：`class ExportPage extends StatefulWidget`，构造参数 `repository` 与 `fileGateway`
- 依赖：Task 5~7 的仓储、控制器与文件出口

- [ ] **Step 1：写失败的组件测试**

新建 `client/test/ui/export_page_test.dart`：

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/backup_codec.dart';
import 'package:local_diary/src/domain/export/file_gateway.dart';
import 'package:local_diary/src/ui/export_page.dart';

import '../support/memory_repository.dart';

class FakeFileGateway implements FileGateway {
  Uint8List? pickResult;
  String? sharedName;
  String? savedName;

  @override
  Future<String?> saveFile({
    required String suggestedName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    savedName = suggestedName;
    return 'content://fake/$suggestedName';
  }

  @override
  Future<Uint8List?> pickFile({
    required String mimeType,
    required List<String> extensions,
  }) async {
    return pickResult;
  }

  @override
  Future<void> shareFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    sharedName = fileName;
  }
}

void main() {
  final time = DateTime.utc(2026, 10, 28, 8);
  Entry entry(String id, String content) => Entry(
    id: id,
    content: content,
    createdAt: time,
    updatedAt: time,
    dayKey: '2026-10-28',
  );

  testWidgets('the page explains that backups stay readable by others', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(
          repository: MemoryRepository(),
          fileGateway: FakeFileGateway(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('明文'), findsWidgets);
  });

  testWidgets('exporting a backup shows the exported count', (tester) async {
    final repo = MemoryRepository();
    repo.entries['a'] = entry('a', '第一条');
    final gateway = FakeFileGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(repository: repo, fileGateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('导出备份（可恢复）'));
    await tester.pumpAndSettle();

    expect(find.text('已导出 1 条'), findsOneWidget);
    expect(gateway.savedName, endsWith('.json'));
  });

  testWidgets('a saved export can be shared from the page', (tester) async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(repository: repo, fileGateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('导出 Markdown（可阅读）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享'));
    await tester.pumpAndSettle();

    expect(gateway.sharedName, endsWith('.md'));
  });

  testWidgets('restoring asks for confirmation before touching the journal', (
    tester,
  ) async {
    final repo = MemoryRepository();
    final backup = const BackupCodec().encode(
      [entry('b', '备份新增')],
      exportedAt: time,
    );
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(utf8.encode(backup));
    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(repository: repo, fileGateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('从备份恢复'));
    await tester.pumpAndSettle();

    expect(find.textContaining('新增 1 条'), findsOneWidget);
    expect(repo.entries, isEmpty);

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(repo.entries['b']!.content, '备份新增');
    expect(find.textContaining('恢复完成'), findsOneWidget);
  });

  testWidgets('a broken backup shows the reason and changes nothing', (
    tester,
  ) async {
    final repo = MemoryRepository();
    final gateway = FakeFileGateway()
      ..pickResult = Uint8List.fromList(utf8.encode('不是备份'));
    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(repository: repo, fileGateway: gateway),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('从备份恢复'));
    await tester.pumpAndSettle();

    expect(find.text('这不是本应用的备份文件'), findsOneWidget);
    expect(repo.entries, isEmpty);
  });
}
```

- [ ] **Step 2：运行测试确认失败**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test test/ui/export_page_test.dart
```

预期：编译失败，提示 `ExportPage` 未定义。

- [ ] **Step 3：写导出页面**

新建 `client/lib/src/ui/export_page.dart`：

```dart
import 'package:flutter/material.dart';

import '../domain/export/file_gateway.dart';
import '../domain/local_entry_repository.dart';
import 'export_controller.dart';

/// 「我的 → 导出与备份」二级页。
class ExportPage extends StatefulWidget {
  const ExportPage({
    super.key,
    required this.repository,
    required this.fileGateway,
  });

  final LocalEntryRepository repository;
  final FileGateway fileGateway;

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  late final ExportController _controller = ExportController(
    repository: widget.repository,
    fileGateway: widget.fileGateway,
  )..addListener(_changed);

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final preview = await _controller.pickBackup();
    if (!mounted || preview == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复这份备份'),
        content: Text(
          '备份里共有 ${preview.total} 条记录。\n'
          '新增 ${preview.inserted} 条，更新 ${preview.updated} 条，'
          '跳过 ${preview.skipped} 条。\n'
          '本机较新的记录不会被覆盖。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final document = _controller.pendingDocument;
    if (document == null) return;
    await _controller.confirmRestore(document);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _controller.status == ExportStatus.working;
    return Scaffold(
      appBar: AppBar(title: const Text('导出与备份')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '备份文件是明文，内容可以用任何文本编辑器打开。'
                '请存放在你自己信任的位置，并注意分享给他人时同样会被看到。',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.7,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            key: const Key('export-backup'),
            leading: const Icon(Icons.archive_outlined),
            title: const Text('导出备份（可恢复）'),
            subtitle: const Text('包含全部记录，可从文件恢复'),
            enabled: !busy,
            onTap: busy ? null : _controller.exportBackup,
          ),
          ListTile(
            key: const Key('export-markdown'),
            leading: const Icon(Icons.description_outlined),
            title: const Text('导出 Markdown（可阅读）'),
            subtitle: const Text('按日期分组，适合阅读与打印'),
            enabled: !busy,
            onTap: busy ? null : _controller.exportMarkdown,
          ),
          ListTile(
            key: const Key('restore-backup'),
            leading: const Icon(Icons.restore),
            title: const Text('从备份恢复'),
            subtitle: const Text('选择备份文件，按修改时间合并'),
            enabled: !busy,
            onTap: busy ? null : _restore,
          ),
          if (_controller.canShare)
            ListTile(
              key: const Key('share-export'),
              leading: const Icon(Icons.share_outlined),
              title: const Text('分享'),
              subtitle: const Text('把刚导出的文件发送到其他应用'),
              enabled: !busy,
              onTap: busy ? null : _controller.shareLastExport,
            ),
          const SizedBox(height: 24),
          if (_controller.status == ExportStatus.working)
            const LinearProgressIndicator(),
          if (_controller.message != null) ...[
            const SizedBox(height: 12),
            Text(
              _controller.message!,
              style: TextStyle(
                color: _controller.status == ExportStatus.failure
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4：接上「我的」页入口并更新说明文案**

修改 `client/lib/src/ui/local_data_page.dart`：把它改成接收仓储，并新增入口。

```dart
import 'package:flutter/material.dart';

import '../domain/local_entry_repository.dart';
import '../platform/saf_file_gateway.dart';
import 'export_page.dart';

class LocalDataPage extends StatelessWidget {
  const LocalDataPage({super.key, required this.repository});
  final LocalEntryRepository repository;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        '我的',
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 24),
      const Card(
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.phone_android_outlined),
              SizedBox(height: 12),
              Text(
                '本地模式',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text('无需账号，离线也能记录。'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.archive_outlined),
        title: const Text('导出与备份'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => ExportPage(
              repository: repository,
              fileGateway: const SafFileGateway(),
            ),
          ),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.privacy_tip_outlined),
        title: const Text('本地数据说明'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('本地数据说明')),
              body: const SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: Text(
                  '当前版本保存日记正文和记录时间，使用应用内的本地数据库。\n\n'
                  '本版本不包含账号、应用内云同步、广告或行为统计，也不会申请麦克风、相机和相册权限。\n\n'
                  '在「导出与备份」里可以手动导出备份文件和 Markdown 文件，'
                  '备份文件是明文，请自行保管。应用不会自动备份，卸载应用或清除数据仍会丢失未导出的记录。',
                  style: TextStyle(fontSize: 16, height: 1.8),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 24),
      Text('本地日记 · 开发预览版', style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
```

修改 `client/lib/src/ui/home_page.dart`：把 `const LocalDataPage()` 换成 `LocalDataPage(repository: widget.repository)`。

- [ ] **Step 5：运行组件测试确认通过**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test test/ui/export_page_test.dart
```

预期：5 项全部通过。

- [ ] **Step 6：提交**

```powershell
git add client/lib/src/ui client/test/ui/export_page_test.dart
git commit -m "feat(F004): add export and backup page"
```

---

### Task 9：全量验证与文档同步

**文件：**
- 新建：`docs/test-reports/F004-导出与备份恢复测试报告-export-and-backup-test-report.md`
- 修改：`docs/test-reports/README.md`
- 修改：`docs/features/README.md`
- 修改：`README.md`、`client/README.md`

**接口：**
- 产出：本次功能的测试报告与台账状态更新

- [ ] **Step 1：格式化**

```powershell
Set-Location D:\dev\myapp\client
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\dart.ps1 format lib test
```

预期：输出 `Formatted N files` 或提示无需改动。

- [ ] **Step 2：静态分析**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 analyze
```

预期：`No issues found!`

- [ ] **Step 3：全量自动化测试**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test --reporter expanded
```

预期：全部通过（原有 27 项 + 本次新增 34 项，共 61 项）。把实际数量写进报告，不要预填。

- [ ] **Step 4：构建调试 APK**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 build apk --debug
```

预期：构建成功。记录耗时与产物路径。若 `file_picker` 或 `share_plus` 与 AGP 9.1.0 冲突，按报错调整依赖版本或补充 Gradle 配置，并把处置写进报告。

- [ ] **Step 5：写测试报告**

新建 `docs/test-reports/F004-导出与备份恢复测试报告-export-and-backup-test-report.md`，按 [测试报告模板](../templates/测试报告模板-test-report-template.md) 填写，至少包含：

- 被测分支 `feat/F004-export-and-backup`、被测版本、环境（Windows、Flutter 3.47.8、Dart 3.13.7）
- 实际执行的命令与真实输出（分析、测试、构建）
- 验收编号 AC-01~AC-10 与对应证据，宿主可验证的写通过
- **真机项单独列出并标为「未执行」**：SAF 保存弹窗、分享面板、选择文件恢复、飞行模式、1000 条量级
- 已知限制：明文备份、Markdown 不转义、备份不含附件与删除标记、全量读入内存

- [ ] **Step 6：更新索引与台账**

在 `docs/test-reports/README.md` 表格增加一行：

```markdown
| F004 | [导出与备份恢复](F004-导出与备份恢复测试报告-export-and-backup-test-report.md) | 2026-10-29 | `feat/F004-export-and-backup` | 自动化测试与静态分析通过；SAF 与分享的真机验收待执行 |
```

把 `docs/features/README.md` 中 F004 的状态改为「待测试」，并在「阻塞项／下一步」列写明真机验收待执行。

- [ ] **Step 7：更新项目说明**

在根 `README.md` 的功能说明中补一句 F004 的能力，并把「在 PowerShell 中运行检查」的命令补上 `test` 的完整用法说明（若已有则不重复添加）。在 `client/README.md` 中列出新增依赖及其用途。

- [ ] **Step 8：提交**

```powershell
git add -A
git commit -m "docs(F004): record export and backup test results"
```

---

### Task 10：合并前检查与合并

**文件：**
- 无新增文件

**接口：**
- 产出：`main` 上包含 F004 的合并提交，本地与远程特性分支保留

- [ ] **Step 1：确认工作区干净**

```powershell
Set-Location D:\dev\myapp
git status --short
```

预期：无输出。

- [ ] **Step 2：合并到 main**

```powershell
git checkout main
git merge --no-ff feat/F004-export-and-backup -m "merge: F004 export and backup recovery"
```

- [ ] **Step 3：在 main 上复跑检查**

```powershell
Set-Location D:\dev\myapp\client
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 analyze
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test
```

预期：分析与测试都通过。

- [ ] **Step 4：确认分支保留**

```powershell
Set-Location D:\dev\myapp
git branch -a
```

预期：`feat/F004-export-and-backup` 仍在列表中；**不要删除**。

- [ ] **Step 5：推送**

```powershell
git push origin main
git push origin feat/F004-export-and-backup
```

推送前先向用户确认；未获授权不推送。

---

## 不在本次范围

- 定时自动备份、备份到云盘（用户可用 SAF 选到网盘目录）
- 备份加密与口令管理
- Markdown 反向导入
- 附件与图片（当前版本没有附件）
- 备份文件签名与校验
- 跨设备自动同步（属于后续的 SyncEngine 编号）
- 清理 `client/test/ui/zz_probe*_test.dart` 等只打印不断言的探针测试（与本功能无关，另行处理）
