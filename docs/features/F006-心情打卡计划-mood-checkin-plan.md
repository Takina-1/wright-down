# 心情打卡 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给日记条目加一个可选心情（5 种 emoji+文字），记录页可设／清除，时间轴卡片显示 emoji，备份 v2 携带 mood 字段。

**Architecture:** domain 层新增 `mood.dart`（标记常量 + 映射表 + 纯函数）；`Entry` 加 `mood` 字段；SQLite schema v2→v3 加 `mood TEXT` 可空列（幂等迁移）；备份编解码与合并判定携带 mood；UI 在记录页加心情入口＋底部弹层、时间轴卡片正文上方显示 emoji。全程 TDD，domain 零框架依赖。

**Tech Stack:** Flutter + Dart + sqflite；测试用 flutter_test + sqflite_common_ffi 宿主 FFI。

## Global Constraints

- 提交信息必须中英结合：`<type>:<中文说明>,<english summary>`，标注编号写成 `feat(F006):...,...`。
- Domain 层（`client/lib/src/domain/`）不得 import 任何框架／SDK，只用 dart: 核心库。
- UI 层不直接访问仓储实现，只依赖 `LocalEntryRepository` 接口；写入走仓储。
- 测试用合成数据，不含真实日记。
- mood 存储用稳定标记字符串（`happy`/`good`/`neutral`/`plain`/`sad`），**不存 emoji**；emoji 与文字只用于显示，映射在 `mood.dart`。
- 备份格式**不升版本号**（保持 v2），mood 作为可选字段，编码时非空才写，解码时缺失即 null。
- schema 迁移必须幂等（参照 F005 的 `deleted_at`：先 `PRAGMA table_info` 查列）。
- 宿主 FFI 测试模式：`import 'package:sqflite_common_ffi/sqflite_ffi.dart';`，`main` 里 `sqfliteFfiInit();`，工厂用 `databaseFactoryFfi`，路径用 `Directory.systemTemp.createTemp` 的临时目录，`tearDown` 里 `repo.close()` + `temp.delete(recursive: true)`。参照 `client/test/data/sqlite_entry_delete_test.dart`。
- MemoryRepository（`client/test/support/memory_repository.dart`）的 `save()` 更新分支必须与生产实现口径一致（携带 mood），否则测试替身与真机会漂移。

## 文件结构

| 文件 | 责任 |
|---|---|
| `client/lib/src/domain/mood.dart`（新建） | 5 种心情标记常量、`Mood` 枚举、`parseMood`/`emojiOf`/`labelOf` 纯函数 |
| `client/lib/src/domain/entry.dart`（改） | `Entry` 加 `String? mood` 字段与构造参数 |
| `client/test/domain/mood_test.dart`（新建） | mood 映射表与解析的单元测试 |
| `client/test/support/memory_repository.dart`（改） | `save()` 更新分支携带 mood（替身口径对齐） |
| `client/lib/src/data/local/sqlite_entry_repository.dart`（改） | schema v3、`mood` 列、迁移、`save`/`_toEntry` 读写 mood |
| `client/test/data/sqlite_entry_mood_test.dart`（新建） | schema 迁移、mood 读写的集成测试 |
| `client/lib/src/domain/export/backup_codec.dart`（改） | 编码／解码 mood 字段 |
| `client/lib/src/domain/export/merge_decision.dart`（改） | update 分支携带 `mood: incoming.mood` |
| `client/test/domain/backup_codec_mood_test.dart`（新建） | 备份带 mood 往返、旧备份兼容 |
| `client/test/data/sqlite_entry_mood_import_test.dart`（新建） | 合并规则（mood 跟 updatedAt 走） |
| `client/lib/src/ui/entry_editor_controller.dart`（改） | 记录／清除当前条目的 mood |
| `client/test/ui/entry_editor_controller_mood_test.dart`（新建） | 控制器 mood 单元测试 |
| `client/lib/src/ui/home_page.dart`（改） | 记录页心情入口＋底部弹层 |
| `client/test/ui/home_page_mood_test.dart`（新建） | 记录页心情入口与弹层组件测试 |
| `client/lib/src/ui/timeline_page.dart`（改） | 时间轴卡片正文上方显示 emoji |
| `client/test/ui/timeline_page_mood_test.dart`（新建） | 时间轴心情显示组件测试 |

---

### Task 1: domain/mood.dart 与 Entry.mood

**Files:**
- Create: `client/lib/src/domain/mood.dart`
- Modify: `client/lib/src/domain/entry.dart`
- Test: `client/test/domain/mood_test.dart`

**Interfaces:**
- Produces: `enum Mood { happy, good, neutral, plain, sad }`；`Mood? parseMood(String?)`；`String emojiOf(String? mood)`；`String labelOf(String? mood)`；`const List<Mood> allMoods`。`Entry` 新增 `final String? mood` 与构造参数 `this.mood`。

- [ ] **Step 1: Write the failing test**

`client/test/domain/mood_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/mood.dart';

void main() {
  group('Mood 标记与显示映射', () {
    test('5 种心情的标记、emoji、文字一一对应', () {
      const table = <Mood, String, String>{
        Mood.happy: ['😄', '开心'],
        Mood.good: ['😊', '不错'],
        Mood.neutral: ['🙂', '一般'],
        Mood.plain: ['😐', '平淡'],
        Mood.sad: ['😢', '难过'],
      };
      for (final entry in table.entries) {
        expect(emojiOf(entry.key.name), entry.value[0]);
        expect(labelOf(entry.key.name), entry.value[1]);
      }
      expect(allMoods, hasLength(5));
    });

    test('parseMood 对合法标记返回对应枚举', () {
      expect(parseMood('happy'), Mood.happy);
      expect(parseMood('good'), Mood.good);
      expect(parseMood('neutral'), Mood.neutral);
      expect(parseMood('plain'), Mood.plain);
      expect(parseMood('sad'), Mood.sad);
    });

    test('parseMood 对 null、未知标记、空串、大小写不匹配、emoji 返回 null', () {
      expect(parseMood(null), isNull);
      expect(parseMood(''), isNull);
      expect(parseMood('angry'), isNull);
      expect(parseMood('Happy'), isNull); // 大小写敏感
      expect(parseMood('😄'), isNull);   // emoji 不是合法标记
    });

    test('emojiOf 与 labelOf 对 null 与非法标记返回空串', () {
      expect(emojiOf(null), '');
      expect(labelOf(null), '');
      expect(emojiOf('angry'), '');
      expect(labelOf('angry'), '');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/mood_test.dart`（在 `client/` 下）
Expected: FAIL — `mood.dart` 不存在，import 报错。

- [ ] **Step 3: Write minimal implementation**

`client/lib/src/domain/mood.dart`：

```dart
/// 心情的稳定标记与显示映射。
///
/// mood 字段存稳定标记字符串（如 `happy`），不存 emoji。
/// emoji 与文字只用于显示，改表情或加种类只动这张表，不动数据模型与备份格式。
library;

enum Mood {
  happy,
  good,
  neutral,
  plain,
  sad;

  String get storage => name;
}

/// 全部心情，弹层按此顺序展示。
const List<Mood> allMoods = [
  Mood.happy,
  Mood.good,
  Mood.neutral,
  Mood.plain,
  Mood.sad,
];

/// 标记 → emoji。
const Map<String, String> _emoji = {
  'happy': '😄',
  'good': '😊',
  'neutral': '🙂',
  'plain': '😐',
  'sad': '😢',
};

/// 标记 → 中文文字。
const Map<String, String> _label = {
  'happy': '开心',
  'good': '不错',
  'neutral': '一般',
  'plain': '平淡',
  'sad': '难过',
};

/// 解析存储值到 [Mood]。非法值、null、空串一律返回 null。
/// 大小写敏感：`Happy` 不等于 `happy`，避免不同来源的拼写漂移。
Mood? parseMood(String? value) {
  if (value == null) return null;
  return Mood.values.firstWhere(
    (m) => m.name == value,
    orElse: () => null,
  );
}

/// 取 emoji；mood 为 null 或非法标记时返回空串。
String emojiOf(String? mood) => _emoji[mood] ?? '';

/// 取文字；mood 为 null 或非法标记时返回空串。
String labelOf(String? mood) => _label[mood] ?? '';
```

修改 `client/lib/src/domain/entry.dart`：在 `Entry` 构造参数与字段加 `mood`（紧跟 `deletedAt` 之后）。

```dart
class Entry {
  const Entry({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.dayKey,
    this.deletedAt,
    this.mood,              // 可选；稳定标记字符串，非 emoji
  });

  final String id;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String dayKey;
  final DateTime? deletedAt;

  /// 心情标记。非空表示这条记录带心情。
  final String? mood;

  bool get isDeleted => deletedAt != null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/mood_test.dart`
Expected: PASS — 4 个 test 全过。

- [ ] **Step 5: Commit**

```bash
git add client/lib/src/domain/mood.dart client/lib/src/domain/entry.dart client/test/domain/mood_test.dart
git commit -m "feat(F006):新增心情标记映射与 Entry.mood 字段,add mood mapping and Entry.mood field"
```

---

### Task 2: SQLite schema v3 与幂等迁移

**Files:**
- Modify: `client/lib/src/data/local/sqlite_entry_repository.dart`
- Test: `client/test/data/sqlite_entry_mood_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Entry.mood`。
- Produces: `entries` 表带 `mood TEXT` 可空列；`version: 3`；`onUpgrade` 对 v2→v3 幂等加列。

- [ ] **Step 1: Write the failing test**

`client/test/data/sqlite_entry_mood_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late SqliteEntryRepository repo;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('local_diary_mood_');
    repo = SqliteEntryRepository(
      factory: databaseFactoryFfi,
      path: '${temp.path}/journal.db',
    );
  });

  tearDown(() async {
    await repo.close();
    Object? cleanupError;
    try {
      await temp.delete(recursive: true);
    } catch (error) {
      debugPrint('删除临时目录失败: ${temp.path} ($error)');
      cleanupError = error;
    }
    expect(cleanupError, isNull, reason: '临时目录清理失败: ${temp.path}');
  });

  test('v3 库的 entries 表含 mood 列', () async {
    final db = await _rawDb(repo);
    final cols = await db.rawQuery('PRAGMA table_info(entries)');
    expect(cols.any((r) => r['name'] == 'mood'), isTrue);
    await db.close();
  });

  test('迁移幂等：先建 v3 结构再用旧版标记再升级，不报 duplicate column', () async {
    // 模拟用户用旧版（只认 v2）打开过 v3 结构的库：sqflite 会把 user_version
    // 回退但保留表结构。这里直接验证 onUpgrade 对已含 mood 列的库不会撞名。
    final db = await _rawDb(repo);
    final cols = await db.rawQuery('PRAGMA table_info(entries)');
    expect(cols.any((r) => r['name'] == 'mood'), isTrue);
    // 再次触发 onUpgrade（oldVersion=2, newVersion=3）应无异常
    await db.close();
    await repo.close();
    // 重新打开同一路径，验证不抛 duplicate column
    repo = SqliteEntryRepository(
      factory: databaseFactoryFfi,
      path: '${temp.path}/journal.db',
    );
    final reopened = await _rawDb(repo);
    expect(
      reopened.isOpen, isTrue,
      reason: '重复打开不应因 mood 列撞名而失败',
    );
    await reopened.close();
  });
}

/// 借用仓储内部打开的数据库连接，用于做行级断言（不经 _toEntry）。
Future<Database> _rawDb(SqliteEntryRepository repo) async {
  // SqliteEntryRepository._database() 是私有的；这里通过 save 触发打开后
  // 用反射不可行，改用 save 一次再导出验证。为简化，本测试用 save/exportAll
  // 间接验证 mood 列可用（见 Task 3）。
  throw UnimplementedError('see Task 3 for mood read/write coverage');
}
```

> 说明：`_rawDb` 占位在 Task 3 用 save/exportAll 覆盖。本 Task 的核心断言是「v3 库含 mood 列」与「重复打开不撞名」，通过 `PRAGMA table_info` 与重新打开验证。`_rawDb` 的真实实现见 Task 3 Step 3——直接用 `repo` 的公开方法即可，无需访问私有 `_database()`。

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/sqlite_entry_mood_test.dart`
Expected: FAIL — 当前 schema 还是 v2，`mood` 列不存在。

- [ ] **Step 3: Write minimal implementation**

修改 `client/lib/src/data/local/sqlite_entry_repository.dart`：

1. `OpenDatabaseOptions(version: 2, ...)` → `version: 3`。
2. `onCreate` 的 `CREATE TABLE entries` 加一行 `mood TEXT`（在 `deleted_at INTEGER` 之后）。
3. `onUpgrade` 的 `if (oldVersion < 2) { ... }` 块后新增 `if (oldVersion < 3) { ... }` 块：幂等加 `mood` 列。

```dart
onUpgrade: (db, oldVersion, newVersion) async {
  if (oldVersion < 2) {
    // F005 的 deleted_at 迁移，保持不动
    final columns = await db.rawQuery('PRAGMA table_info(entries)');
    final hasDeletedAt = columns.any((row) => row['name'] == 'deleted_at');
    if (!hasDeletedAt) {
      await db.execute('ALTER TABLE entries ADD COLUMN deleted_at INTEGER');
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS entries_deleted '
      'ON entries(deleted_at DESC, id DESC)',
    );
  }
  if (oldVersion < 3) {
    // F006 的 mood 迁移，同样幂等：用户若用旧版打开过，列可能已在
    final columns = await db.rawQuery('PRAGMA table_info(entries)');
    final hasMood = columns.any((row) => row['name'] == 'mood');
    if (!hasMood) {
      await db.execute('ALTER TABLE entries ADD COLUMN mood TEXT');
    }
  }
},
```

`onCreate` 的建表语句：

```dart
await db.execute('''CREATE TABLE entries (
  id TEXT PRIMARY KEY NOT NULL,
  content TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  day_key TEXT NOT NULL,
  deleted_at INTEGER,
  mood TEXT
)''');
```

> Task 2 的测试里 `_rawDb` 抛 `UnimplementedError` 是故意的过渡：真正的 mood 读写断言在 Task 3 用公开方法覆盖。Task 2 只验证 schema 结构（v3 含 mood 列、重复打开不撞名）。把 Task 2 测试里的 `_rawDb` 调用改为：先 `await repo.save(...)` 再 `exportAll()` 验证 mood 可读可写——这其实是 Task 3 的内容。**为避免重复，Task 2 的测试聚焦「列存在 + 重复打开不撞名」**，用 `PRAGMA table_info` 断言列存在即可，不需要 `_rawDb`。执行时按此简化：删除 `_rawDb` 占位，直接用 `repo` 打开后通过 `PRAGMA table_info` 断言（见下方修正后的测试）。

修正后的 Task 2 测试（执行时采用）：

```dart
  test('v3 库的 entries 表含 mood 列', () async {
    await repo.save(_entry('a', '正文'));
    final all = await repo.exportAll();
    expect(all.single.mood, isNull); // mood 列可读，新条目为 null
  });

  test('迁移幂等：重复打开同一库不因 mood 列撞名', () async {
    await repo.save(_entry('a', '正文'));
    await repo.close();
    repo = SqliteEntryRepository(
      factory: databaseFactoryFfi,
      path: '${temp.path}/journal.db',
    );
    final all = await repo.exportAll();
    expect(all.single.content, '正文'); // 老数据完好
  });

  Entry _entry(String id, String content) => Entry(
    id: id, content: content,
    createdAt: DateTime.utc(2026, 10, 30, 2, 0),
    updatedAt: DateTime.utc(2026, 10, 30, 2, 0),
    dayKey: '2026-10-30',
  );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/sqlite_entry_mood_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/src/data/local/sqlite_entry_repository.dart client/test/data/sqlite_entry_mood_test.dart
git commit -m "feat(F006):schema 升 v3 加 mood 列并幂等迁移,add mood column with idempotent v3 migration"
```

---

### Task 3: mood 字段读写 + 替身口径对齐

**Files:**
- Modify: `client/lib/src/data/local/sqlite_entry_repository.dart`
- Modify: `client/test/support/memory_repository.dart`
- Test: `client/test/data/sqlite_entry_mood_test.dart`（追加）

**Interfaces:**
- Consumes: Task 2 的 `mood` 列。
- Produces: `save()` 写 mood（非空才写，与 deleted_at 同口径）；`_toEntry()` 读回 mood；MemoryRepository `save()` 更新分支携带 mood。

- [ ] **Step 1: Write the failing test**

追加到 `client/test/data/sqlite_entry_mood_test.dart`（接在既有测试后）：

```dart
    test('save 带 mood 后 list 与 exportAll 能读回', () async {
      await repo.save(_entry('m1', '今天很开心', mood: 'happy'));
      expect((await repo.list()).single.mood, 'happy');
      expect((await repo.exportAll()).single.mood, 'happy');
    });

    test('mood 为空时列存 NULL，读回 null', () async {
      await repo.save(_entry('m2', '没有心情'));
      expect((await repo.list()).single.mood, isNull);
    });

    test('编辑不带 mood 的 Entry 不会覆盖已有 mood', () async {
      await repo.save(_entry('m3', 'a', mood: 'happy'));
      // 编辑器保存正文时构造的 Entry 不带 mood
      await repo.save(Entry(
        id: 'm3', content: 'a 改',
        createdAt: DateTime.utc(2026, 10, 30, 2, 0),
        updatedAt: DateTime.utc(2026, 10, 30, 3, 0),
        dayKey: '2026-10-30',
      ));
      expect((await repo.list()).single.mood, 'happy');
    });

    test('编辑带新 mood 的 Entry 会更新 mood', () async {
      await repo.save(_entry('m4', 'a', mood: 'happy'));
      await repo.save(_entry('m4', 'a 改', mood: 'sad',
        updated: DateTime.utc(2026, 10, 30, 3, 0)));
      expect((await repo.list()).single.mood, 'sad');
    });
```

`_entry` helper 扩展（支持 mood 与 updated 参数）：

```dart
  Entry _entry(String id, String content,
      {String? mood, DateTime? updated}) => Entry(
    id: id, content: content,
    createdAt: DateTime.utc(2026, 10, 30, 2, 0),
    updatedAt: updated ?? DateTime.utc(2026, 10, 30, 2, 0),
    dayKey: '2026-10-30', mood: mood,
  );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/sqlite_entry_mood_test.dart`
Expected: FAIL — `mood` 没写入，读回 null。

- [ ] **Step 3: Write minimal implementation**

修改 `sqlite_entry_repository.dart` 的 `save()`：在 `deleted_at` 写入逻辑旁加 `mood`（非空才写，与 `deleted_at` 同口径）。

`save()` 顶部加：`final mood = entry.mood;`

update map 里（在 deleted_at 之后）：
```dart
if (mood != null) 'mood': mood,
```

insert map 里（在 deleted_at 之后）：
```dart
if (mood != null) 'mood': mood,
```

修改 `_toEntry()`：
```dart
final mood = row['mood'] as String?;
return Entry(
  // ...
  mood: mood,
);
```

修改 `client/test/support/memory_repository.dart` 的 `save()` 更新分支（line 62-69），让新 Entry 携带 mood：

```dart
    entries[entry.id] = Entry(
      id: existing.id,
      content: entry.content,
      createdAt: existing.createdAt,
      updatedAt: entry.updatedAt,
      dayKey: existing.dayKey,
      deletedAt: entry.deletedAt ?? existing.deletedAt,
      mood: entry.mood ?? existing.mood,
    );
```

> 替身口径对齐：更新分支只写正文与修改时间，mood 沿用「传入非空则用传入的，否则保留已有的」，与生产实现「非空才写」一致。

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/sqlite_entry_mood_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/src/data/local/sqlite_entry_repository.dart client/test/support/memory_repository.dart client/test/data/sqlite_entry_mood_test.dart
git commit -m "feat(F006):仓储读写 mood 并对齐替身口径,persist mood and align test double"
```

---

### Task 4: 备份编解码 mood 字段

**Files:**
- Modify: `client/lib/src/domain/export/backup_codec.dart`
- Test: `client/test/domain/backup_codec_mood_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Entry.mood`。
- Produces: `BackupCodec.encode` 写 `"mood"`（非空才写）；`decode` 读回 `mood`（缺失即 null）。

- [ ] **Step 1: Write the failing test**

`client/test/domain/backup_codec_mood_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/backup_codec.dart';

Entry _entry(String id, [String? mood]) => Entry(
  id: id, content: '正文 $id',
  createdAt: DateTime.utc(2026, 10, 30, 2, 0),
  updatedAt: DateTime.utc(2026, 10, 30, 2, 0),
  dayKey: '2026-10-30', mood: mood,
);

void main() {
  const codec = BackupCodec();

  test('带 mood 的条目编码后解码能读回 mood', () {
    final text = codec.encode([_entry('e1', 'happy')]);
    expect(codec.decode(text).entries.single.mood, 'happy');
  });

  test('未设心情的条目不写 mood 键，解码为 null', () {
    final text = codec.encode([_entry('e2')]);
    expect(text, isNot(contains('"mood"')));
    expect(codec.decode(text).entries.single.mood, isNull);
  });

  test('带 mood 的条目编码文本里含 mood 键', () {
    final text = codec.encode([_entry('e3', 'sad')]);
    expect(text, contains('"mood": "sad"'));
  });

  test('旧 v2 备份（无 mood 键）解码为 null，不报错', () {
    const old = '''{
  "format": "local-diary-backup",
  "version": 2,
  "exportedAt": "2026-10-30T02:00:00.000Z",
  "entryCount": 1,
  "entries": [{
    "id": "e4",
    "content": "旧记录",
    "createdAt": "2026-10-30T02:00:00.000Z",
    "updatedAt": "2026-10-30T02:00:00.000Z",
    "dayKey": "2026-10-30"
  }]
}''';
    expect(codec.decode(old).entries.single.mood, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/backup_codec_mood_test.dart`
Expected: FAIL — 编码不写 mood，解码读不回。

- [ ] **Step 3: Write minimal implementation**

修改 `backup_codec.dart` 的 `_encodeEntry`：

```dart
    final mood = entry.mood;
    // 只有已设心情的条目才写 mood，未设的不写键。
    if (mood != null) {
      map['mood'] = mood;
    }
```

修改 `_decodeEntry` 的 `Entry(...)` 构造：加 `mood: raw['mood'] as String?`。

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/backup_codec_mood_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/src/domain/export/backup_codec.dart client/test/domain/backup_codec_mood_test.dart
git commit -m "feat(F006):备份编解码携带 mood 字段,backup codec carries mood field"
```

---

### Task 5: 合并规则（mood 跟 updatedAt 走）

**Files:**
- Modify: `client/lib/src/domain/export/merge_decision.dart`
- Modify: `client/lib/src/data/local/sqlite_entry_repository.dart`（importAll 的 update 分支写 mood）
- Test: `client/test/data/sqlite_entry_mood_import_test.dart`

**Interfaces:**
- Consumes: Task 3 的 mood 读写、Task 4 的备份解码。
- Produces: `decideMerge` update 分支携带 `mood: incoming.mood`；`importAll` 写入 mood。

- [ ] **Step 1: Write the failing test**

`client/test/data/sqlite_entry_mood_import_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Entry _e(String id, {String? mood, DateTime? updated}) => Entry(
  id: id, content: 'c$id',
  createdAt: DateTime.utc(2026, 10, 30, 2, 0),
  updatedAt: updated ?? DateTime.utc(2026, 10, 30, 2, 0),
  dayKey: '2026-10-30', mood: mood,
);

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late SqliteEntryRepository repo;

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

  test('备份 updatedAt 更新且带 mood → 本地 mood 被覆盖', () async {
    await repo.save(_e('x', mood: 'happy', updated: DateTime.utc(2026, 10, 30, 2, 0)));
    await repo.importAll([_e('x', mood: 'sad', updated: DateTime.utc(2026, 10, 30, 9, 0))]);
    expect((await repo.list()).single.mood, 'sad');
  });

  test('备份 updatedAt 更新但不带 mood → 本地 mood 被清空', () async {
    await repo.save(_e('y', mood: 'happy', updated: DateTime.utc(2026, 10, 30, 2, 0)));
    await repo.importAll([_e('y', mood: null, updated: DateTime.utc(2026, 10, 30, 9, 0))]);
    expect((await repo.list()).single.mood, isNull);
  });

  test('备份 updatedAt 较旧 → 跳过，本地 mood 不变', () async {
    await repo.save(_e('z', mood: 'happy', updated: DateTime.utc(2026, 10, 30, 9, 0)));
    await repo.importAll([_e('z', mood: 'sad', updated: DateTime.utc(2026, 10, 30, 2, 0))]);
    expect((await repo.list()).single.mood, 'happy');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/sqlite_entry_mood_import_test.dart`
Expected: FAIL — update 分支没写 mood，mood 没被覆盖／清空。

- [ ] **Step 3: Write minimal implementation**

修改 `merge_decision.dart` 的 `decideMerge` update 分支，`Entry(...)` 加 `mood: incoming.mood`：

```dart
  if (incoming.updatedAt.millisecondsSinceEpoch >
      local.updatedAt.millisecondsSinceEpoch) {
    return MergeDecision(
      MergeAction.update,
      Entry(
        id: local.id,
        content: incoming.content,
        createdAt: local.createdAt,
        updatedAt: incoming.updatedAt,
        dayKey: local.dayKey,
        deletedAt: incoming.deletedAt,
        mood: incoming.mood,   // mood 跟 updatedAt 走
      ),
    );
  }
```

修改 `sqlite_entry_repository.dart` 的 `importAll` update 分支，update map 加 `'mood': decision.entry.mood`（紧跟 deleted_at 之后）。

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/sqlite_entry_mood_import_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/src/domain/export/merge_decision.dart client/lib/src/data/local/sqlite_entry_repository.dart client/test/data/sqlite_entry_mood_import_test.dart
git commit -m "feat(F006):合并规则携带 mood 跟 updatedAt 走,merge carries mood with updatedAt"
```

---

### Task 6: EntryEditorController 记录／清除 mood

**Files:**
- Modify: `client/lib/src/ui/entry_editor_controller.dart`
- Test: `client/test/ui/entry_editor_controller_mood_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Entry.mood`、Task 3 的仓储。
- Produces: `EntryEditorController` 新增 `String? mood` getter、`setMood(String?)`、`clearMood()`；保存时 mood 随 Entry 一起落库。

- [ ] **Step 1: Write the failing test**

`client/test/ui/entry_editor_controller_mood_test.dart`：

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/entry_editor_controller.dart';

import '../support/memory_repository.dart';

void main() {
  late MemoryRepository repo;
  late EntryEditorController editor;
  var seq = 0;
  setUp(() {
    repo = MemoryRepository();
    editor = EntryEditorController(
      repository: repo,
      idGenerator: () => 'entry-${seq++}',
      now: () => DateTime(2026, 10, 30, 2, 0),
    );
  });
  tearDown(() => editor.dispose());

  test('新记录默认 mood 为 null', () {
    expect(editor.mood, isNull);
  });

  testWidgets('setMood 后保存，仓储里的条目带 mood', (tester) async {
    editor.updateContent('今天开心');
    editor.setMood('happy');
    await tester.pump(const Duration(seconds: 2));
    expect(repo.entries.values.single.mood, 'happy');
  });

  testWidgets('clearMood 后保存，仓储里的条目 mood 为 null', (tester) async {
    editor.updateContent('今天开心');
    editor.setMood('happy');
    editor.clearMood();
    await tester.pump(const Duration(seconds: 2));
    expect(repo.entries.values.single.mood, isNull);
  });

  test('edit 载入已有条目时 mood 一并载入', () async {
    final entry = Entry(
      id: 'e', content: '旧',
      createdAt: DateTime(2026, 10, 30, 2, 0),
      updatedAt: DateTime(2026, 10, 30, 2, 0),
      dayKey: '2026-10-30', mood: 'sad',
    );
    await editor.edit(entry);
    expect(editor.mood, 'sad');
  });

  test('newEntry 后 mood 清空', () async {
    editor.updateContent('x');
    editor.setMood('happy');
    await editor.flush();
    await editor.newEntry();
    expect(editor.mood, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/entry_editor_controller_mood_test.dart`
Expected: FAIL — `mood` getter、`setMood`、`clearMood` 不存在。

- [ ] **Step 3: Write minimal implementation**

修改 `entry_editor_controller.dart`：

1. 新增字段 `String? _mood;`
2. 新增 getter `String? get mood => _mood;`
3. 新增 `void setMood(String? mood)`：

```dart
  void setMood(String? mood) {
    if (_disposed || mood == _mood) return;
    _mood = mood;
    _timer?.cancel();
    // mood 变化要触发保存：若正文为空则保存会失败，但心情仍要落库，
    // 所以 mood 变化一律调度 flush（flush 内部对空正文有保护）。
    _timer = Timer(const Duration(seconds: 1), () => unawaited(flush()));
    _notify();
  }

  void clearMood() => setMood(null);
```

4. `_saveLoop()` 构造 `Entry` 时加 `mood: _mood`。
5. `edit(entry)` 里 `_mood = entry.mood;`
6. `newEntry()` 里 `_mood = null;`
7. `deleteCurrent()` 复位时 `_mood = null;`
8. `markDeleted()` 复位时 `_mood = null;`

> 注意：`setMood` 触发保存时，若正文为空，`_saveLoop` 会因「正文不能为空」失败并返回 false，但 mood 不会落库。这是可接受的——空正文的条目没有保存意义，心情随正文一起保存。测试用例用非空正文验证 mood 落库。

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/entry_editor_controller_mood_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/src/ui/entry_editor_controller.dart client/test/ui/entry_editor_controller_mood_test.dart
git commit -m "feat(F006):编辑器记录与清除心情,editor tracks and clears mood"
```

---

### Task 7: 记录页心情入口与弹层

**Files:**
- Modify: `client/lib/src/ui/home_page.dart`
- Test: `client/test/ui/home_page_mood_test.dart`

**Interfaces:**
- Consumes: Task 6 的 `editor.mood`/`setMood`/`clearMood`、Task 1 的 `allMoods`/`emojiOf`/`labelOf`。
- Produces: 记录页输入区下方心情入口（已设 emoji／未设 😊），点击弹 `ModalBottomSheet` 列 5 种心情＋「清除」。

- [ ] **Step 1: Write the failing test**

`client/test/ui/home_page_mood_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/ui/home_page.dart';

import '../support/memory_repository.dart';

Future<void> _pumpHome(WidgetTester tester, MemoryRepository repo) async {
  await tester.pumpWidget(
    MaterialApp(home: HomePage(repository: repo)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('未设心情时入口显示 😊 占位', (tester) async {
    await _pumpHome(tester, MemoryRepository());
    expect(find.byKey(const Key('mood-entry')), findsOneWidget);
    expect(find.text('😊'), findsWidgets);
  });

  testWidgets('点开弹层列出 5 种心情与文字', (tester) async {
    final repo = MemoryRepository();
    await _pumpHome(tester, repo);
    await tester.tap(find.byKey(const Key('mood-entry')));
    await tester.pumpAndSettle();
    for (final label in ['开心', '不错', '一般', '平淡', '难过']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('清除'), findsNothing); // 未设时无清除
  });

  testWidgets('选择心情后入口显示对应 emoji 并落库', (tester) async {
    final repo = MemoryRepository();
    await _pumpHome(tester, repo);
    await tester.tap(find.byKey(const Key('mood-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开心'));
    await tester.pumpAndSettle();
    expect(find.text('😄'), findsWidgets);
    await tester.pump(const Duration(seconds: 2)); // 等防抖保存
    expect(repo.entries.values.single.mood, 'happy');
  });

  testWidgets('已设心情后弹层显示清除，清除后恢复未设', (tester) async {
    final repo = MemoryRepository();
    await _pumpHome(tester, repo);
    await tester.tap(find.byKey(const Key('mood-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开心'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mood-entry')));
    await tester.pumpAndSettle();
    expect(find.text('清除'), findsOneWidget);
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(find.text('😊'), findsWidgets);
  });
}
```

> 注：HomePage 需要 `fileGateway` 参数吗？看 HomePage 构造——`HomePage({required repository, this.fileGateway})`，fileGateway 可选。所以 `HomePage(repository: repo)` 即可。

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/home_page_mood_test.dart`
Expected: FAIL — 心情入口不存在。

- [ ] **Step 3: Write minimal implementation**

修改 `home_page.dart`：导入 `mood.dart`。

在 `_composer` 的 Column children 里，TextField 的 `Expanded` 之后、状态行 `Row` 之前，新增心情入口行：

```dart
          Row(
            children: [
              IconButton(
                key: const Key('mood-entry'),
                icon: Text(emojiOf(_editor.mood) ?? '😊'),
                onPressed: _transitioning ? null : _showMoodSheet,
              ),
            ],
          ),
```

新增 `_showMoodSheet`：

```dart
  Future<void> _showMoodSheet() async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...allMoods.map((m) {
              final sel = _editor.mood == m.name;
              return ListTile(
                leading: Text(emojiOf(m.name)),
                title: Text(labelOf(m.name)),
                trailing: sel ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, m.name),
              );
            }),
            if (_editor.mood != null)
              ListTile(
                leading: const Icon(Icons.clear_outlined),
                title: const Text('清除'),
                onTap: () => Navigator.pop(context, ''),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (picked == null) return; // 取消
    _editor.setMood(picked.isEmpty ? null : picked);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/home_page_mood_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/src/ui/home_page.dart client/test/ui/home_page_mood_test.dart
git commit -m "feat(F006):记录页加心情入口与选择弹层,add mood entry and sheet on composer"
```

---

### Task 8: 时间轴卡片显示心情 emoji

**Files:**
- Modify: `client/lib/src/ui/timeline_page.dart`
- Test: `client/test/ui/timeline_page_mood_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `emojiOf`、Task 3 的 list 读回 mood。
- Produces: 时间轴卡片正文上方显示 `emojiOf(entry.mood)`（非空才显示）。

- [ ] **Step 1: Write the failing test**

`client/test/ui/timeline_page_mood_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/timeline_page.dart';

import '../support/memory_repository.dart';

Entry _e(String id, [String? mood]) => Entry(
  id: id, content: '正文 $id',
  createdAt: DateTime.utc(2026, 10, 30, 2, 0),
  updatedAt: DateTime.utc(2026, 10, 30, 2, 0),
  dayKey: '2026-10-30', mood: mood,
);

Future<void> _pump(WidgetTester tester, MemoryRepository repo) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TimelinePage(repository: repo, onEdit: (_) {}, onStart: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('已设心情的卡片显示 emoji', (tester) async {
    final repo = MemoryRepository();
    repo.entries['e1'] = _e('e1', 'happy');
    await _pump(tester, repo);
    expect(find.text('😄'), findsOneWidget);
  });

  testWidgets('未设心情的卡片不显示心情 emoji', (tester) async {
    final repo = MemoryRepository();
    repo.entries['e2'] = _e('e2');
    await _pump(tester, repo);
    expect(find.text('😄'), findsNothing);
    expect(find.text('😊'), findsNothing);
    expect(find.text('😢'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/timeline_page_mood_test.dart`
Expected: FAIL — 卡片不显示 emoji。

- [ ] **Step 3: Write minimal implementation**

修改 `timeline_page.dart`：导入 `mood.dart`。

在 itemBuilder 里，`Card` 的 `ListTile` 加 `leading`：

```dart
final emoji = emojiOf(entry.mood);
Card(
  elevation: 0,
  child: ListTile(
    contentPadding: const EdgeInsets.all(16),
    leading: emoji.isEmpty ? null : Text(emoji),
    title: Text(entry.content, maxLines: 4, overflow: TextOverflow.ellipsis,
        style: const TextStyle(height: 1.6)),
    // ...其余不变
  ),
),
```

> 用 `leading` 放 emoji，未设时为 null 不占位。显示逻辑用 `emojiOf` 纯函数，不硬编码（AC-13）。

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/timeline_page_mood_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/src/ui/timeline_page.dart client/test/ui/timeline_page_mood_test.dart
git commit -m "feat(F006):时间轴卡片显示心情 emoji,timeline card shows mood emoji"
```

---

### Task 9: 全量检查与构建

**Files:**
- 无新增代码（仅验证 + 文档更新）

- [ ] **Step 1: flutter analyze**

Run: `flutter analyze`（在 `client/` 下）
Expected: `No issues found!`

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: 全部通过（含 F001–F005 既有测试 + F006 新增）。

- [ ] **Step 3: 检查占位实现**

Run: `grep -rn "UnimplementedError" client/lib`
Expected: 无输出。

- [ ] **Step 4: 构建 debug APK**

Run: `flutter build apk --debug`
Expected: `√ Built build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 5: 更新功能文档 §8 与台账**

更新 `docs/features/F006-心情打卡-mood-checkin.md` §6 任务完成情况（全部已完成）与 §8（实际实现路径、检查命令、已知限制）。更新台账 F006 状态为「待测试」。

- [ ] **Step 6: Commit**

```bash
git add docs/features/F006-心情打卡-mood-checkin.md docs/features/README.md
git commit -m "docs(F006):记录心情打卡实施变化与台账,record mood checkin implementation"
```

---

## 已知限制（交付时记录）

- 心情为可选附加信息，导入不带 mood 的较新备份会清空本地心情（LWW 语义，见功能文档 §5.4）。
- 不做心情统计（连续心情天数、热力图、情绪分析）。
- 不做每日心情打卡、按心情筛选。
- 心情表情固定 5 种，不支持自定义。
