# F005 删除记录与回收站 · 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户能删掉写错的记录，并且删错了能在回收站里找回来；同时保证已删除的条目不会被旧备份恢复「诈尸」。

**Architecture:** 沿用项目既有的本地优先分层——domain 层放纯 Dart 的模型与判定，data 层放 SQLite 实现，ui 层放控制器与页面。删除采用软删除：SQLite 表加一列 `deleted_at`，时间轴查询过滤掉已删除条目，条目本体留在库里。备份格式从 `version: 1` 升到 `version: 2`，条目可携带 `deletedAt` 删除标记，从而把「已删除」这一状态随备份文件一起传播。

**Tech Stack:** Flutter 3.47.8 / Dart 3.13.7、sqflite 2.4.5（Android）、sqflite_common_ffi 2.4.5（宿主集成测试）、flutter_test。

**规格：** `docs/features/F005-删除记录与回收站-entry-delete-and-trash.md`

## Global Constraints

以下约束对每个任务都生效，评审时按这些逐条核对：

- **备份与 Markdown 均为明文**，不做加密；备份文件带删除标记后仍是明文，界面需写明这一点。
- **删除一律是软删除**：任何「删除」入口都必须走 `softDelete`，不得直接物理删除；只有回收站里的「彻底删除」和「清空回收站」才物理移除。
- **已删除条目不得被未删除的备份复活**：本地 `deleted_at` 非空而备份条目未删除时，合并一律判定为跳过，不看 `updatedAt`。
- **备份格式固定** `format: "local-diary-backup"`、`version: 2`；`version: 1` 的旧备份必须仍可导入；`version > 2` 拒绝并提示升级；`version < 1` 判损坏。
- **时间在备份与数据库中统一使用 UTC ISO-8601 / epoch 毫秒**；备份里的时间串必须带 `Z` 或显式时区偏移，否则判损坏。`dayKey` 保留写入当天的本地日期。
- **合并判定与时间比较统一按毫秒精度**（`millisecondsSinceEpoch >`），预览与实际导入必须调用同一份判定函数。
- **Domain 层不得 import 任何框架或 SDK**；`Entry`、`LocalEntryRepository`、备份编解码、合并判定全部保持纯 Dart。
- **正文不做转义**，Markdown 正文与换行原样输出。
- **删除相关失败必须显式提示**，不得静默消失；条目必须留在原位。
- **提交信息中英结合**，格式 `<type>:<中文说明>,<english summary>`，例如 `feat(F005):新增软删除与回收站,add soft delete and trash`。
- **不新增任何依赖**：本功能不需要新的 pub 包。
- **`MemoryRepository` 与 `test/support/entry_merger.dart` 必须与生产实现同规则**：改了合并规则，两个替身都要跟着改，且要有用例锁定。

---

## 文件结构

**新增**

```text
client/lib/src/domain/export/merge_decision.dart   合并判定：本地与备份两条目如何合并（纯 Dart）
client/lib/src/ui/trash_page.dart                   回收站二级页
client/test/domain/entry_test.dart                  Entry.deletedAt 的域层单测
client/test/domain/merge_decision_test.dart         合并判定单测
client/test/data/sqlite_schema_migration_test.dart  schema v1 → v2 迁移集成测试
client/test/data/sqlite_entry_delete_test.dart      仓储删除相关方法的集成测试
client/test/ui/trash_page_test.dart                 回收站组件测试
```

**修改**

```text
client/lib/src/domain/entry.dart                          新增 deletedAt
client/lib/src/domain/local_entry_repository.dart         新增 5 个方法，list/exportAll 语义变化
client/lib/src/domain/export/backup_document.dart         kBackupVersion 升 2，entries 不可变
client/lib/src/domain/export/backup_codec.dart            v1/v2 编解码与额外校验
client/lib/src/domain/export/markdown_exporter.dart       只渲染未删除条目
client/lib/src/domain/export/restore_preview.dart         改用 decideMerge
client/lib/src/data/local/sqlite_entry_repository.dart    schema v2、迁移、5 个新方法、list 过滤、importAll 用 decideMerge
client/lib/src/ui/entry_editor_controller.dart             canDelete、currentEntryId、deleteCurrent
client/lib/src/ui/timeline_page.dart                      长按菜单、删除、撤销
client/lib/src/ui/home_page.dart                          记录页删除按钮
client/lib/src/ui/local_data_page.dart                    回收站入口与本地数据说明文案
client/lib/src/ui/export_controller.dart                  导出失败原因透出、导出条数口径
client/test/support/memory_repository.dart                实现新接口
client/test/support/entry_merger.dart                    改用 decideMerge
```

---

### Task 1: 域模型与仓库接口

**Files:**
- Modify: `client/lib/src/domain/entry.dart`
- Modify: `client/lib/src/domain/local_entry_repository.dart`
- Modify: `client/test/support/memory_repository.dart`
- Test: `client/test/domain/entry_test.dart`

**Interfaces:**
- Consumes: 无（起点任务）
- Produces:
  - `Entry.deletedAt`（`DateTime?`，可选命名参数，默认 `null`）、`Entry.isDeleted`（`bool` getter）
  - `LocalEntryRepository.listDeleted({int limit = 30})` → `Future<List<Entry>>`
  - `LocalEntryRepository.softDelete(String id)` → `Future<void>`
  - `LocalEntryRepository.restore(String id)` → `Future<void>`
  - `LocalEntryRepository.purge(String id)` → `Future<void>`
  - `LocalEntryRepository.purgeAll()` → `Future<int>`
  - `list()` 语义收紧为「只含未删除条目」；`exportAll()` 语义放宽为「含已删除条目」

- [ ] **Step 1: 写失败的测试**

新建 `client/test/domain/entry_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';

void main() {
  group('Entry', () {
    test('默认没有删除时间', () {
      final entry = Entry(
        id: 'a',
        content: '正文',
        createdAt: DateTime.utc(2026, 10, 28),
        updatedAt: DateTime.utc(2026, 10, 28),
        dayKey: '2026-10-28',
      );
      expect(entry.deletedAt, isNull);
      expect(entry.isDeleted, isFalse);
    });

    test('带删除时间时视为已删除', () {
      final entry = Entry(
        id: 'a',
        content: '正文',
        createdAt: DateTime.utc(2026, 10, 28),
        updatedAt: DateTime.utc(2026, 10, 28),
        dayKey: '2026-10-28',
        deletedAt: DateTime.utc(2026, 10, 30),
      );
      expect(entry.isDeleted, isTrue);
      expect(entry.deletedAt, DateTime.utc(2026, 10, 30));
    });

    test('dayKey 合法性判断', () {
      expect(isValidDayKey('2026-10-28'), isTrue);
      expect(isValidDayKey('2026-1-8'), isFalse);
      expect(isValidDayKey('2026'), isFalse);
      expect(isValidDayKey(''), isFalse);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/domain/entry_test.dart`
Expected: FAIL — `Entry` 没有 `deletedAt` 也没有 `isDeleted`，编译错误。

- [ ] **Step 3: 实现 `Entry.deletedAt`**

修改 `client/lib/src/domain/entry.dart`，把 `Entry` 换成：

```dart
class Entry {
  const Entry({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.dayKey,
    this.deletedAt,
  });

  final String id;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String dayKey;

  /// 删除时间。非空表示这条已被软删除：数据仍在库里，但不该出现在时间轴上。
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
}
```

`deletedAt` 必须是**可选命名参数**，这样现有所有构造 `Entry` 的代码（生产与测试）都不用改。

- [ ] **Step 4: 扩展仓库接口**

把 `client/lib/src/domain/local_entry_repository.dart` 换成：

```dart
import 'entry.dart';
import 'export/import_summary.dart';

abstract interface class LocalEntryRepository {
  Future<void> save(Entry entry);

  /// 时间轴列表：只含未删除条目，按创建时间倒序。
  Future<List<Entry>> list({EntryCursor? before, int limit = 30});

  /// 导出用：一次取出全部条目（含已删除条目），按创建时间倒序排列，不受分页限制。
  /// 含已删除条目是为了让备份携带删除标记，恢复时不会把已删条目复活。
  Future<List<Entry>> exportAll();

  /// 回收站列表：只含已删除条目，按删除时间倒序。
  Future<List<Entry>> listDeleted({int limit = 30});

  /// 软删除：标记删除时间。条目从时间轴消失，但数据保留，可在回收站找回。
  Future<void> softDelete(String id);

  /// 从回收站恢复：清除删除标记，条目回到时间轴，创建时间与正文不变。
  Future<void> restore(String id);

  /// 彻底删除：物理移除该条目，不可再恢复。
  Future<void> purge(String id);

  /// 清空回收站：物理移除所有已删除条目，返回移除条数。
  Future<int> purgeAll();

  /// 恢复用：按条目 ID 合并导入。备份较新才覆盖，本地较新一律跳过；
  /// 本地已删除的条目不会被未删除的备份复活。
  /// 整个导入在一个事务内完成，失败时整体回滚。
  Future<ImportSummary> importAll(List<Entry> entries);

  Future<void> close();
}
```

- [ ] **Step 5: 让 `MemoryRepository` 跟上新接口**

`client/test/support/memory_repository.dart` 至少要补上这五个方法与 `list` 的过滤，否则编译不过。实现要点：

- 构造参数加 `DateTime Function()? now`，默认 `DateTime.now`，用于给软删除/恢复打时间戳，保证用例可预期。
- `list()` 只返回 `deletedAt == null` 的条目，保持原有排序与分页。
- `exportAll()` 返回全部条目（含已删除），保持原有排序。
- `listDeleted()` 返回 `deletedAt != null` 的条目，按 `deletedAt` 倒序、`id` 倒序。
- `softDelete(id)`：找不到条目时抛 `StateError`；命中时把 `deletedAt` 与 `updatedAt` 一起置为 `now()`。
- `restore(id)`：只对 `deletedAt != null` 的条目生效，否则抛 `StateError`；命中时清空 `deletedAt` 并把 `updatedAt` 置为 `now()`。
- `purge(id)`：从 map 里移除；不存在时抛 `StateError`。
- `purgeAll()`：移除所有已删除条目，返回移除条数。

示例（`softDelete`）：

```dart
  @override
  Future<void> softDelete(String id) async {
    if (failDelete) throw StateError('simulated delete failure');
    final existing = entries[id];
    if (existing == null) throw StateError('no such entry: $id');
    final stamp = _now().toUtc();
    entries[id] = Entry(
      id: existing.id,
      content: existing.content,
      createdAt: existing.createdAt,
      updatedAt: stamp,
      dayKey: existing.dayKey,
      deletedAt: stamp,
    );
  }
```

同时加一个 `bool failDelete = false;` 字段用于制造删除失败场景（Task 8、Task 9 会用到）。

- [ ] **Step 6: 运行测试确认通过**

Run: `cd client && flutter analyze && flutter test test/domain/entry_test.dart`
Expected: `analyze` 无问题；`entry_test.dart` 3 项通过。

- [ ] **Step 7: 提交**

```bash
git add client/lib/src/domain/entry.dart client/lib/src/domain/local_entry_repository.dart client/test/support/memory_repository.dart client/test/domain/entry_test.dart
git commit -m "feat(F005):新增删除标记与仓库接口,add deletion flag and repository contract"
```

---

### Task 2: SQLite schema 升到 v2 并支持迁移

**Files:**
- Modify: `client/lib/src/data/local/sqlite_entry_repository.dart`
- Test: `client/test/data/sqlite_schema_migration_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Entry.deletedAt`
- Produces: `entries` 表新增 `deleted_at INTEGER`（可空）；`SqliteEntryRepository` 用 `version: 2` 打开数据库，老库自动迁移

- [ ] **Step 1: 写失败的测试**

新建 `client/test/data/sqlite_schema_migration_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('version 1 的库升级到 version 2 后老数据完好且删除标记为空', () async {
    final factory = databaseFactoryFfi;
    final path = '${await factory.getDatabasesPath()}/migration_test.db';
    await factory.deleteDatabase(path);

    // 先按旧版本建库并写入数据。
    final legacy = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE entries (
            id TEXT PRIMARY KEY NOT NULL,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            day_key TEXT NOT NULL
          )''');
        },
      ),
    );
    await legacy.insert('entries', {
      'id': 'legacy-1',
      'content': '升级前写下的记录',
      'created_at': DateTime.utc(2026, 10, 28).millisecondsSinceEpoch,
      'updated_at': DateTime.utc(2026, 10, 28).millisecondsSinceEpoch,
      'day_key': '2026-10-28',
    });
    await legacy.close();

    final repository = SqliteEntryRepository(factory: factory, path: path);
    final entries = await repository.exportAll();
    expect(entries, hasLength(1));
    expect(entries.single.content, '升级前写下的记录');
    expect(entries.single.deletedAt, isNull);
    await repository.close();

    await factory.deleteDatabase(path);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/data/sqlite_schema_migration_test.dart`
Expected: FAIL — 仓储仍以 `version: 1` 打开，不会触发迁移；断言 `deletedAt` 为空时 `Entry` 还没有该字段，编译错误。

- [ ] **Step 3: 实现 schema v2 与迁移**

修改 `client/lib/src/data/local/sqlite_entry_repository.dart` 的 `_database()`，把 `OpenDatabaseOptions` 换成：

```dart
        options: OpenDatabaseOptions(
          version: 2,
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
              day_key TEXT NOT NULL,
              deleted_at INTEGER
            )''');
            await db.execute(
              'CREATE INDEX entries_timeline ON entries(created_at DESC, id DESC)',
            );
            await db.execute('CREATE INDEX entries_day ON entries(day_key)');
            await db.execute(
              'CREATE INDEX entries_deleted ON entries(deleted_at DESC, id DESC)',
            );
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) {
              // 加一个可空列即可：老行读出来是 NULL，等价于「未删除」，
              // 不需要重写任何数据。
              await db.execute(
                'ALTER TABLE entries ADD COLUMN deleted_at INTEGER',
              );
              await db.execute(
                'CREATE INDEX IF NOT EXISTS entries_deleted '
                'ON entries(deleted_at DESC, id DESC)',
              );
            }
          },
        ),
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter analyze && flutter test test/data/sqlite_schema_migration_test.dart`
Expected: `analyze` 无问题；迁移测试通过。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/data/local/sqlite_entry_repository.dart client/test/data/sqlite_schema_migration_test.dart
git commit -m "feat(F005):数据库升级到版本二并新增删除列,upgrade schema to v2 with deleted column"
```

---

### Task 3: 仓储的删除、恢复与回收站查询

**Files:**
- Modify: `client/lib/src/data/local/sqlite_entry_repository.dart`
- Test: `client/test/data/sqlite_entry_delete_test.dart`

**Interfaces:**
- Consumes: Task 1 的接口、Task 2 的 schema
- Produces: `SqliteEntryRepository` 实现 `listDeleted` / `softDelete` / `restore` / `purge` / `purgeAll`；`list()` 过滤已删除；`exportAll()` 含已删除；`_toEntry` 读出 `deleted_at`

- [ ] **Step 1: 写失败的测试**

新建 `client/test/data/sqlite_entry_delete_test.dart`。参考既有 `client/test/data/sqlite_entry_repository_test.dart` 的建库与清理写法，覆盖：

- 软删除后 `list()` 不再返回该条目，`exportAll()` 仍返回且 `deletedAt` 非空。
- `listDeleted()` 只返回已删除条目，按删除时间倒序。
- `restore()` 后 `list()` 重新返回该条目，`deletedAt` 为空，`content` 与 `createdAt` 与删除前一致。
- `purge()` 后 `exportAll()` 不再返回该条目。
- `purgeAll()` 只清掉已删除条目，未删除条目不受影响，返回条数正确。
- `softDelete` 对不存在的 ID 抛 `StateError`；`restore` 对未删除条目抛 `StateError`；`purge` 对不存在的 ID 抛 `StateError`。

示例骨架：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/local/sqlite_entry_repository.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late SqliteEntryRepository repository;

  setUp(() async {
    final factory = databaseFactoryFfi;
    final path = '${await factory.getDatabasesPath()}/delete_test.db';
    await factory.deleteDatabase(path);
    repository = SqliteEntryRepository(factory: factory, path: path);
  });

  tearDown(() async {
    await repository.close();
  });

  Entry entry(String id, {String content = '正文', String day = '2026-10-28'}) =>
      Entry(
        id: id,
        content: content,
        createdAt: DateTime.utc(2026, 10, 28, 3),
        updatedAt: DateTime.utc(2026, 10, 28, 3),
        dayKey: day,
      );

  test('软删除后时间轴不再返回该条目，但导出仍能拿到删除标记', () async {
    await repository.save(entry('a'));
    await repository.softDelete('a');

    expect(await repository.list(), isEmpty);
    final exported = await repository.exportAll();
    expect(exported, hasLength(1));
    expect(exported.single.deletedAt, isNotNull);
  });

  test('回收站只列出已删除条目', () async {
    await repository.save(entry('a'));
    await repository.save(entry('b'));
    await repository.softDelete('b');

    final trash = await repository.listDeleted();
    expect(trash.map((e) => e.id), ['b']);
  });

  test('恢复后条目回到时间轴且创建时间不变', () async {
    await repository.save(entry('a'));
    final before = (await repository.exportAll()).single;
    await repository.softDelete('a');
    await repository.restore('a');

    final after = (await repository.list()).single;
    expect(after.id, 'a');
    expect(after.createdAt, before.createdAt);
    expect(after.deletedAt, isNull);
  });

  test('彻底删除后条目不再存在', () async {
    await repository.save(entry('a'));
    await repository.softDelete('a');
    await repository.purge('a');

    expect(await repository.exportAll(), isEmpty);
    expect(await repository.listDeleted(), isEmpty);
  });

  test('清空回收站只清掉已删除条目', () async {
    await repository.save(entry('a'));
    await repository.save(entry('b'));
    await repository.softDelete('b');

    expect(await repository.purgeAll(), 1);
    expect(await repository.listDeleted(), isEmpty);
    expect((await repository.list()).single.id, 'a');
  });

  test('对不存在的条目操作会抛错', () async {
    expect(() => repository.softDelete('nope'), throwsStateError);
    expect(() => repository.purge('nope'), throwsStateError);
  });

  test('恢复一个未删除的条目会抛错', () async {
    await repository.save(entry('a'));
    expect(() => repository.restore('a'), throwsStateError);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/data/sqlite_entry_delete_test.dart`
Expected: FAIL — `softDelete` 等方法尚未实现，编译错误。

- [ ] **Step 3: 实现仓储方法**

修改 `client/lib/src/data/local/sqlite_entry_repository.dart`：

`list()` 改为只查未删除条目：

```dart
  @override
  Future<List<Entry>> list({EntryCursor? before, int limit = 30}) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    final db = await _database();
    final rows = await db.query(
      'entries',
      where: before == null
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND (created_at < ? OR (created_at = ? AND id < ?))',
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
```

`exportAll()` 保持不过滤（已删除条目也要导出，备份要带删除标记）。若当前实现里有 `where` 条件，保持原样即可，确认它没有过滤 `deleted_at`。

新增五个方法：

```dart
  @override
  Future<List<Entry>> listDeleted({int limit = 30}) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    final db = await _database();
    final rows = await db.query(
      'entries',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(_toEntry).toList();
  }

  @override
  Future<void> softDelete(String id) async {
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
    final db = await _database();
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final updated = await db.update(
      'entries',
      {'deleted_at': stamp, 'updated_at': stamp},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated == 0) {
      throw StateError('No such entry: $id');
    }
  }

  @override
  Future<void> restore(String id) async {
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
    final db = await _database();
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final updated = await db.update(
      'entries',
      {'deleted_at': null, 'updated_at': stamp},
      where: 'id = ? AND deleted_at IS NOT NULL',
      whereArgs: [id],
    );
    if (updated == 0) {
      throw StateError('Entry $id is not in the trash');
    }
  }

  @override
  Future<void> purge(String id) async {
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
    final db = await _database();
    final deleted = await db.delete(
      'entries',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deleted == 0) {
      throw StateError('No such entry: $id');
    }
  }

  @override
  Future<int> purgeAll() async {
    final db = await _database();
    return db.delete('entries', where: 'deleted_at IS NOT NULL');
  }
```

`_toEntry` 读出删除时间：

```dart
  Entry _toEntry(Map<String, Object?> row) {
    final deletedAt = row['deleted_at'] as int?;
    return Entry(
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
      deletedAt: deletedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(deletedAt, isUtc: true),
    );
  }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter analyze && flutter test test/data/sqlite_entry_delete_test.dart`
Expected: `analyze` 无问题；7 项测试通过。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/data/local/sqlite_entry_repository.dart client/test/data/sqlite_entry_delete_test.dart
git commit -m "feat(F005):实现软删除恢复与回收站查询,implement soft delete restore and trash queries"
```

---

### Task 4: 备份编解码升到 v2 并兼容 v1

**Files:**
- Modify: `client/lib/src/domain/export/backup_document.dart`
- Modify: `client/lib/src/domain/export/backup_codec.dart`
- Modify: `client/lib/src/ui/export_controller.dart`
- Test: `client/test/domain/backup_codec_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Entry.deletedAt`
- Produces:
  - `kBackupVersion = 2`、`kMinBackupVersion = 1`
  - `BackupDocument.entries` 为不可变列表
  - `BackupCodec.encode` 产出 `version: 2`，已删除条目带 `deletedAt`
  - `BackupCodec.decode` 同时接受 v1（无删除标记）与 v2
  - `BackupFormatException` 的 `reason` 同时用于「无法编码」与「无法解码」两种失败

- [ ] **Step 1: 写失败的测试**

在 `client/test/domain/backup_codec_test.dart` 中追加：

```dart
  group('备份格式版本 2', () {
    test('已删除条目编码后带 deletedAt，解码后能读回', () {
      final codec = BackupCodec();
      final deleted = Entry(
        id: 'a',
        content: '写错了',
        createdAt: DateTime.utc(2026, 10, 28, 3),
        updatedAt: DateTime.utc(2026, 10, 30, 1),
        dayKey: '2026-10-28',
        deletedAt: DateTime.utc(2026, 10, 30, 1),
      );
      final live = Entry(
        id: 'b',
        content: '正常记录',
        createdAt: DateTime.utc(2026, 10, 29, 3),
        updatedAt: DateTime.utc(2026, 10, 29, 3),
        dayKey: '2026-10-29',
      );

      final text = codec.encode([deleted, live]);
      expect(text, contains('"version": 2'));
      expect(text, contains('deletedAt'));

      final document = codec.decode(text);
      expect(document.version, 2);
      expect(document.entries, hasLength(2));
      expect(document.entries.first.deletedAt, DateTime.utc(2026, 10, 30, 1));
      expect(document.entries.last.deletedAt, isNull);
    });

    test('version 1 的旧备份仍可导入，且条目一律视为未删除', () {
      const legacy = '''{
        "format": "local-diary-backup",
        "version": 1,
        "exportedAt": "2026-10-28T02:00:00.000Z",
        "entryCount": 1,
        "entries": [
          {
            "id": "old-1",
            "content": "旧版本写的记录",
            "createdAt": "2026-10-28T02:00:00.000Z",
            "updatedAt": "2026-10-28T02:00:00.000Z",
            "dayKey": "2026-10-28"
          }
        ]
      }''';
      final document = const BackupCodec().decode(legacy);
      expect(document.version, 1);
      expect(document.entries.single.deletedAt, isNull);
    });

    test('version 为 0 判损坏', () {
      expect(
        () => const BackupCodec().decode('{"format":"local-diary-backup","version":0,'
            '"exportedAt":"2026-10-28T02:00:00.000Z","entryCount":0,"entries":[]}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('version 高于当前支持时提示升级', () {
      expect(
        () => const BackupCodec().decode('{"format":"local-diary-backup","version":3,'
            '"exportedAt":"2026-10-28T02:00:00.000Z","entryCount":0,"entries":[]}'),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.reason,
            'reason',
            '备份来自更新的版本，请先升级应用',
          ),
        ),
      );
    });

    test('entryCount 与实际条数不符判损坏', () {
      expect(
        () => const BackupCodec().decode('{"format":"local-diary-backup","version":2,'
            '"exportedAt":"2026-10-28T02:00:00.000Z","entryCount":9,"entries":[]}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('时间串缺时区偏移判损坏', () {
      expect(
        () => const BackupCodec().decode('{"format":"local-diary-backup","version":2,'
            '"exportedAt":"2026-10-28T02:00:00","entryCount":0,"entries":[]}'),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/domain/backup_codec_test.dart`
Expected: FAIL — 现有实现写 `version: 1`、不解 `deletedAt`、`entryCount` 不校验、时间串无时区要求。

- [ ] **Step 3: 升级备份文档与编解码**

`client/lib/src/domain/export/backup_document.dart` 换成：

```dart
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
```

注意：`BackupDocument` 的构造函数不再是 `const`。若有地方写了 `const BackupDocument(...)`，去掉 `const`。

`client/lib/src/domain/export/backup_codec.dart` 换成：

```dart
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
```

- [ ] **Step 4: 导出控制器透出失败原因、修正条数口径**

`client/lib/src/ui/export_controller.dart`：

- `_export` 的参数增加 `required int Function(List<Entry> entries) count`，用来算提示里的条数：备份文件写的是全部条目（含已删除），Markdown 只写未删除条目，两者条数口径不同。
- `_export` 的 `catch` 之前加一条 `on BackupFormatException` 分支，把 `error.reason` 直接作为提示文案。

```dart
  Future<bool> exportBackup() => _export(
    extension: 'json',
    mimeType: 'application/json',
    count: (entries) => entries.length,
    encode: (entries) => _codec.encode(entries, exportedAt: _now()),
  );

  Future<bool> exportMarkdown() => _export(
    extension: 'md',
    mimeType: 'text/markdown',
    count: (entries) => _markdownExporter.visibleCount(entries),
    encode: (entries) => _markdownExporter.render(entries, exportedAt: _now()),
  );
```

`_export` 内部：

```dart
  Future<bool> _export({
    required String extension,
    required String mimeType,
    required int Function(List<Entry> entries) count,
    required String Function(List<Entry> entries) encode,
  }) async {
    ...
      final entries = await repository.exportAll();
      final bytes = Uint8List.fromList(utf8.encode(encode(entries)));
      ...
      _message = '已导出 ${count(entries)} 条';
    ...
    } on BackupFormatException catch (error) {
      debugPrint('导出失败：${error.reason}');
      _status = ExportStatus.failure;
      _message = error.reason;
      _notify();
      return false;
    } catch (error) {
      ...
    }
  }
```

`MarkdownExporter.visibleCount` 在 Task 6 实现；本任务先把调用写上，Task 6 补齐方法即可（Task 6 之前 `flutter analyze` 会报未定义，所以**本任务的 Step 6 与 Task 6 之间不要单独跑 analyze**；或者把 `visibleCount` 一并在本任务里加到 `markdown_exporter.dart`——**推荐后者**，避免中间状态编译不过）。

因此在 `client/lib/src/domain/export/markdown_exporter.dart` 里同时加上：

```dart
  /// 可读导出只渲染未删除条目，条数与渲染结果一致。
  int visibleCount(List<Entry> entries) =>
      entries.where((entry) => entry.deletedAt == null).length;
```

（`render` 的过滤留到 Task 6 一并做。）

- [ ] **Step 5: 运行测试确认通过**

Run: `cd client && flutter analyze && flutter test test/domain/backup_codec_test.dart test/ui/export_controller_test.dart`
Expected: `analyze` 无问题；编解码与导出控制器测试全部通过。

注意：既有 `backup_codec_test.dart` 里若有断言 `version: 1` 或 `entryCount` 行为的用例，需要按新规则更新（`version` 改为 2）。既有 `export_controller_test.dart` 里若有断言「已导出 N 条」的用例，条数口径按上面的 `count` 保持不变（替身 `MemoryRepository.exportAll()` 返回全部条目，未删除条目数相同）。

- [ ] **Step 6: 提交**

```bash
git add client/lib/src/domain/export/backup_document.dart client/lib/src/domain/export/backup_codec.dart client/lib/src/domain/export/markdown_exporter.dart client/lib/src/ui/export_controller.dart client/test/domain/backup_codec_test.dart
git commit -m "feat(F005):备份格式升到版本二并兼容旧版,upgrade backup format to v2 with legacy support"
```

---

### Task 5: 合并判定统一实现

**Files:**
- Create: `client/lib/src/domain/export/merge_decision.dart`
- Modify: `client/lib/src/domain/export/restore_preview.dart`
- Modify: `client/lib/src/data/local/sqlite_entry_repository.dart`
- Modify: `client/test/support/entry_merger.dart`
- Test: `client/test/domain/merge_decision_test.dart`
- Test: `client/test/domain/restore_preview_test.dart`（补充用例）
- Test: `client/test/data/sqlite_entry_import_test.dart`（补充用例）

**Interfaces:**
- Consumes: Task 1 的 `Entry.deletedAt`
- Produces:
  - `enum MergeAction { insert, update, skip }`
  - `class MergeDecision { final MergeAction action; final Entry entry; }`
  - `MergeDecision decideMerge({Entry? local, required Entry incoming})`
  - `restore_preview.dart` 的 `compareRestore` 改用 `decideMerge`
  - SQLite `importAll` 与 `test/support/entry_merger.dart` 改用 `decideMerge`

- [ ] **Step 1: 写失败的测试**

新建 `client/test/domain/merge_decision_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/merge_decision.dart';

void main() {
  Entry entry({
    String id = 'a',
    String content = '正文',
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => Entry(
    id: id,
    content: content,
    createdAt: DateTime.utc(2026, 10, 28, 3),
    updatedAt: updatedAt ?? DateTime.utc(2026, 10, 28, 3),
    dayKey: '2026-10-28',
    deletedAt: deletedAt,
  );

  test('本地没有这条时插入', () {
    final decision = decideMerge(local: null, incoming: entry());
    expect(decision.action, MergeAction.insert);
    expect(decision.entry.id, 'a');
  });

  test('本地已删除而备份未删除时跳过，不复活', () {
    final decision = decideMerge(
      local: entry(deletedAt: DateTime.utc(2026, 10, 30, 1)),
      incoming: entry(updatedAt: DateTime.utc(2026, 11, 1)),
    );
    expect(decision.action, MergeAction.skip);
  });

  test('备份更新时更新正文，创建时间以本地为准', () {
    final decision = decideMerge(
      local: entry(content: '旧正文'),
      incoming: entry(content: '新正文', updatedAt: DateTime.utc(2026, 11, 1)),
    );
    expect(decision.action, MergeAction.update);
    expect(decision.entry.content, '新正文');
    expect(decision.entry.createdAt, DateTime.utc(2026, 10, 28, 3));
  });

  test('备份更新且带删除标记时，本地条目变为已删除', () {
    final decision = decideMerge(
      local: entry(),
      incoming: entry(
        updatedAt: DateTime.utc(2026, 11, 1),
        deletedAt: DateTime.utc(2026, 11, 1),
      ),
    );
    expect(decision.action, MergeAction.update);
    expect(decision.entry.deletedAt, DateTime.utc(2026, 11, 1));
  });

  test('备份不比本地新时跳过', () {
    final decision = decideMerge(
      local: entry(updatedAt: DateTime.utc(2026, 11, 1)),
      incoming: entry(updatedAt: DateTime.utc(2026, 10, 1)),
    );
    expect(decision.action, MergeAction.skip);
  });

  test('毫秒精度比较：同一毫秒内不更新', () {
    final decision = decideMerge(
      local: entry(updatedAt: DateTime.utc(2026, 11, 1, 0, 0, 0, 500)),
      incoming: entry(updatedAt: DateTime.utc(2026, 11, 1, 0, 0, 0, 500)),
    );
    expect(decision.action, MergeAction.skip);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/domain/merge_decision_test.dart`
Expected: FAIL — `merge_decision.dart` 不存在。

- [ ] **Step 3: 实现合并判定**

新建 `client/lib/src/domain/export/merge_decision.dart`：

```dart
import '../entry.dart';

/// 一条备份条目与本地条目合并后的处置。
enum MergeAction { insert, update, skip }

/// 合并判定结果。
class MergeDecision {
  const MergeDecision(this.action, this.entry);

  final MergeAction action;

  /// 合并后应当写入的条目。action 为 skip 时没有意义。
  final Entry entry;
}

/// 判定一条备份条目如何并入本地。
///
/// 预览（compareRestore）与实际导入（仓储层）必须调用这同一个函数，
/// 否则预告的条数和实际写入的条数会对不上。
///
/// 规则：
/// - 本地没有这条 → 插入。
/// - 本地已删除而备份未删除 → 跳过。本地删除优先，备份不能把它复活。
/// - 备份 updatedAt 更新 → 更新正文与删除状态；创建时间与 dayKey 以本地为准。
/// - 其余 → 跳过。
///
/// 时间比较按毫秒精度，与 SQLite 存储层一致。
MergeDecision decideMerge({Entry? local, required Entry incoming}) {
  if (local == null) {
    return MergeDecision(MergeAction.insert, incoming);
  }
  if (local.deletedAt != null && incoming.deletedAt == null) {
    return MergeDecision(MergeAction.skip, local);
  }
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
      ),
    );
  }
  return MergeDecision(MergeAction.skip, local);
}
```

- [ ] **Step 4: 预览改用同一份判定**

`client/lib/src/domain/export/restore_preview.dart` 的 `compareRestore` 换成：

```dart
import '../entry.dart';
import 'merge_decision.dart';

/// 按 ID 与修改时间比较本地和备份，给出这次恢复会改动什么。
/// 判断规则由 [decideMerge] 统一提供，与仓储层的合并实现完全一致：
/// 预览的条数和实际导入的条数不会对不上。
RestorePreview compareRestore(List<Entry> local, List<Entry> incoming) {
  final byId = {for (final entry in local) entry.id: entry};
  var inserted = 0;
  var updated = 0;
  var skipped = 0;
  for (final entry in incoming) {
    switch (decideMerge(local: byId[entry.id], incoming: entry).action) {
      case MergeAction.insert:
        inserted++;
      case MergeAction.update:
        updated++;
      case MergeAction.skip:
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

- [ ] **Step 5: SQLite 导入改用同一份判定**

`client/lib/src/data/local/sqlite_entry_repository.dart` 的 `importAll` 换成：

```dart
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
        // dayKey 必须是合法日期键：它决定了时间轴的月份分组，
        // 脏数据会让回顾页按字符串切月时崩溃。
        if (!isValidDayKey(entry.dayKey)) {
          throw ArgumentError('An imported entry needs a valid day key');
        }
        final rows = await txn.query(
          'entries',
          where: 'id = ?',
          whereArgs: [entry.id],
          limit: 1,
        );
        final local = rows.isEmpty ? null : _toEntry(rows.first);
        final decision = decideMerge(local: local, incoming: entry);
        switch (decision.action) {
          case MergeAction.insert:
            await txn.insert('entries', {
              'id': decision.entry.id,
              'content': decision.entry.content,
              'created_at': decision.entry.createdAt.millisecondsSinceEpoch,
              'updated_at': decision.entry.updatedAt.millisecondsSinceEpoch,
              'day_key': decision.entry.dayKey,
              'deleted_at':
                  decision.entry.deletedAt?.millisecondsSinceEpoch,
            });
            inserted++;
          case MergeAction.update:
            await txn.update(
              'entries',
              {
                'content': decision.entry.content,
                'updated_at': decision.entry.updatedAt.millisecondsSinceEpoch,
                'deleted_at':
                    decision.entry.deletedAt?.millisecondsSinceEpoch,
              },
              where: 'id = ?',
              whereArgs: [entry.id],
            );
            updated++;
          case MergeAction.skip:
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
```

并在该文件顶部加 `import '../../domain/export/merge_decision.dart';`。

- [ ] **Step 6: 测试替身改用同一份判定**

`client/test/support/entry_merger.dart` 的 `mergeEntries` 换成：

```dart
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/import_summary.dart';
import 'package:local_diary/src/domain/export/merge_decision.dart';

/// 测试替身共用的合并实现。
///
/// 先整批校验并算出结果，全部通过后才一次性写入；任何一条出错就抛出，
/// 目标 map 保持原样——与生产实现的单事务回滚语义一致。
/// 判定规则与生产实现共用 [decideMerge]，包括「本地已删除不复活」。
ImportSummary mergeEntries(Map<String, Entry> store, List<Entry> incoming) {
  final pending = <String, Entry>{};
  var inserted = 0;
  var updated = 0;
  var skipped = 0;
  for (final entry in incoming) {
    if (entry.id.isEmpty) {
      throw ArgumentError('An imported entry needs an id');
    }
    // 与生产仓储一致：dayKey 不合法就整体拒绝导入。
    if (!isValidDayKey(entry.dayKey)) {
      throw ArgumentError('An imported entry needs a valid day key');
    }
    final existing = pending[entry.id] ?? store[entry.id];
    final decision = decideMerge(local: existing, incoming: entry);
    switch (decision.action) {
      case MergeAction.insert:
        pending[entry.id] = decision.entry;
        inserted++;
      case MergeAction.update:
        pending[entry.id] = decision.entry;
        updated++;
      case MergeAction.skip:
        skipped++;
    }
  }
  store.addAll(pending);
  return ImportSummary(inserted: inserted, updated: updated, skipped: skipped);
}
```

- [ ] **Step 7: 补充用例**

在 `client/test/domain/restore_preview_test.dart` 追加：

```dart
  test('本地已删除的条目不会被备份复活，计入跳过', () {
    final deleted = Entry(
      id: 'a',
      content: '正文',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 30),
      dayKey: '2026-10-28',
      deletedAt: DateTime.utc(2026, 10, 30),
    );
    final incoming = Entry(
      id: 'a',
      content: '正文',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 11, 1),
      dayKey: '2026-10-28',
    );
    final preview = compareRestore([deleted], [incoming]);
    expect(preview.inserted, 0);
    expect(preview.updated, 0);
    expect(preview.skipped, 1);
  });
```

在 `client/test/data/sqlite_entry_import_test.dart` 追加：

```dart
  test('本地已删除的条目不会被备份复活', () async {
    await repository.save(entry('a', content: '原本的正文'));
    await repository.softDelete('a');

    final incoming = Entry(
      id: 'a',
      content: '备份里的正文',
      createdAt: DateTime.utc(2026, 10, 28, 3),
      updatedAt: DateTime.utc(2026, 11, 1),
      dayKey: '2026-10-28',
    );
    final summary = await repository.importAll([incoming]);

    expect(summary.skipped, 1);
    expect(summary.updated, 0);
    expect(await repository.list(), isEmpty);
    expect((await repository.listDeleted()).single.content, '原本的正文');
  });

  test('备份里带删除标记的条目会把本地条目标记为已删除', () async {
    await repository.save(entry('a'));

    final incoming = Entry(
      id: 'a',
      content: '备份里的正文',
      createdAt: DateTime.utc(2026, 10, 28, 3),
      updatedAt: DateTime.utc(2026, 11, 1),
      dayKey: '2026-10-28',
      deletedAt: DateTime.utc(2026, 11, 1),
    );
    final summary = await repository.importAll([incoming]);

    expect(summary.updated, 1);
    expect(await repository.list(), isEmpty);
    expect((await repository.listDeleted()).single.id, 'a');
  });
```

（`entry(...)` 辅助函数按该测试文件里既有的写法调整。）

- [ ] **Step 8: 运行测试确认通过**

Run: `cd client && flutter analyze && flutter test test/domain/merge_decision_test.dart test/domain/restore_preview_test.dart test/data/sqlite_entry_import_test.dart test/support/entry_merger_test.dart`
Expected: `analyze` 无问题；四组测试全部通过。

- [ ] **Step 9: 提交**

```bash
git add client/lib/src/domain/export/merge_decision.dart client/lib/src/domain/export/restore_preview.dart client/lib/src/data/local/sqlite_entry_repository.dart client/test/support/entry_merger.dart client/test/domain/merge_decision_test.dart client/test/domain/restore_preview_test.dart client/test/data/sqlite_entry_import_test.dart
git commit -m "feat(F005):统一合并判定并禁止已删条目复活,unify merge decision and block resurrection"
```

---

### Task 6: Markdown 导出排除已删除条目

**Files:**
- Modify: `client/lib/src/domain/export/markdown_exporter.dart`
- Test: `client/test/domain/markdown_exporter_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Entry.deletedAt`（Task 4 已加 `visibleCount`）
- Produces: `MarkdownExporter.render` 只渲染未删除条目；头部 `entryCount` 与渲染条数一致

- [ ] **Step 1: 写失败的测试**

在 `client/test/domain/markdown_exporter_test.dart` 追加：

```dart
  test('已删除的条目不进入可读导出', () {
    final deleted = Entry(
      id: 'a',
      content: '写错了',
      createdAt: DateTime.utc(2026, 10, 28, 3),
      updatedAt: DateTime.utc(2026, 10, 30, 1),
      dayKey: '2026-10-28',
      deletedAt: DateTime.utc(2026, 10, 30, 1),
    );
    final live = Entry(
      id: 'b',
      content: '正常记录',
      createdAt: DateTime.utc(2026, 10, 29, 3),
      updatedAt: DateTime.utc(2026, 10, 29, 3),
      dayKey: '2026-10-29',
    );

    final markdown = const MarkdownExporter().render([deleted, live]);

    expect(markdown, isNot(contains('写错了')));
    expect(markdown, contains('正常记录'));
    expect(markdown, contains('entryCount: 1'));
  });

  test('visibleCount 与渲染条数一致', () {
    final entries = [
      Entry(
        id: 'a',
        content: '已删除',
        createdAt: DateTime.utc(2026, 10, 28, 3),
        updatedAt: DateTime.utc(2026, 10, 28, 3),
        dayKey: '2026-10-28',
        deletedAt: DateTime.utc(2026, 10, 30, 1),
      ),
      Entry(
        id: 'b',
        content: '正常',
        createdAt: DateTime.utc(2026, 10, 29, 3),
        updatedAt: DateTime.utc(2026, 10, 29, 3),
        dayKey: '2026-10-29',
      ),
    ];
    expect(const MarkdownExporter().visibleCount(entries), 1);
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/domain/markdown_exporter_test.dart`
Expected: FAIL — 已删除条目仍被渲染。

- [ ] **Step 3: 实现过滤**

`client/lib/src/domain/export/markdown_exporter.dart` 的 `render` 开头改为：

```dart
  String render(List<Entry> entries, {DateTime? exportedAt}) {
    // 可读导出只给还在时间轴上的条目看：已删除的记录不该出现在阅读稿里。
    final visible = entries.where((entry) => entry.deletedAt == null).toList();
    final stamp = (exportedAt ?? DateTime.now()).toUtc().toIso8601String();
    final sorted = [...visible]
      ..sort((a, b) {
        final byDay = b.dayKey.compareTo(a.dayKey);
        if (byDay != 0) return byDay;
        final byTime = b.createdAt.compareTo(a.createdAt);
        if (byTime != 0) return byTime;
        return b.id.compareTo(a.id);
      });
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('exportedAt: $stamp')
      ..writeln('entryCount: ${visible.length}')
      ..writeln('---')
      ...
```

其余渲染逻辑不变。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter analyze && flutter test test/domain/markdown_exporter_test.dart`
Expected: `analyze` 无问题；全部通过。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/domain/export/markdown_exporter.dart client/test/domain/markdown_exporter_test.dart
git commit -m "feat(F005):可读导出排除已删除条目,exclude deleted entries from markdown export"
```

---

### Task 7: 编辑器支持删除当前条目

**Files:**
- Modify: `client/lib/src/ui/entry_editor_controller.dart`
- Test: `client/test/ui/entry_editor_controller_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `LocalEntryRepository.softDelete`
- Produces:
  - `EntryEditorController.canDelete` → `bool`
  - `EntryEditorController.currentEntryId` → `String?`
  - `EntryEditorController.deleteError` → `String?`
  - `EntryEditorController.deleteCurrent()` → `Future<bool>`

- [ ] **Step 1: 写失败的测试**

在 `client/test/ui/entry_editor_controller_test.dart` 追加：

```dart
  test('新记录不可删除', () async {
    final controller = EntryEditorController(
      repository: repository,
      idGenerator: () => 'new-1',
      now: () => DateTime.utc(2026, 10, 28),
    );
    controller.updateContent('还没保存的内容');
    expect(controller.canDelete, isFalse);
    expect(controller.currentEntryId, isNull);
  });

  test('编辑已有条目时可以删除，删除后编辑器复位', () async {
    final controller = EntryEditorController(
      repository: repository,
      idGenerator: () => 'unused',
      now: () => DateTime.utc(2026, 10, 28),
    );
    final entry = Entry(
      id: 'saved-1',
      content: '写错了',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
      dayKey: '2026-10-28',
    );
    await controller.edit(entry);
    expect(controller.canDelete, isTrue);
    expect(controller.currentEntryId, 'saved-1');

    expect(await controller.deleteCurrent(), isTrue);

    expect(controller.canDelete, isFalse);
    expect(controller.currentEntryId, isNull);
    expect(controller.content, isEmpty);
    expect(repository.entries['saved-1']!.deletedAt, isNotNull);
  });

  test('删除失败时保留内容并给出错误', () async {
    final controller = EntryEditorController(
      repository: repository,
      idGenerator: () => 'unused',
      now: () => DateTime.utc(2026, 10, 28),
    );
    await controller.edit(
      Entry(
        id: 'saved-1',
        content: '写错了',
        createdAt: DateTime.utc(2026, 10, 28),
        updatedAt: DateTime.utc(2026, 10, 28),
        dayKey: '2026-10-28',
      ),
    );
    repository.failDelete = true;

    expect(await controller.deleteCurrent(), isFalse);
    expect(controller.content, '写错了');
    expect(controller.error, isNotNull);
    expect(repository.entries['saved-1']!.deletedAt, isNull);
  });
```

（`repository` 为该测试文件里既有的 `MemoryRepository` 实例；`failDelete` 由 Task 1 提供。）

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/ui/entry_editor_controller_test.dart`
Expected: FAIL — `canDelete` / `currentEntryId` / `deleteCurrent` 不存在。

- [ ] **Step 3: 实现**

`client/lib/src/ui/entry_editor_controller.dart` 增加：

```dart
  /// 当前是否正在编辑一条已保存的条目。新记录没有可删除的对象。
  bool get canDelete => _persisted && _id != null;

  /// 当前编辑的条目 ID；编辑新记录时为 null。
  String? get currentEntryId => _id;
```

以及方法：

```dart
  /// 删除当前编辑的条目。
  ///
  /// 先把未保存的修改落盘再删除，删除成功后编辑器复位为空白的新记录。
  /// 返回 true 表示删除成功；不是已保存的条目或删除失败时返回 false。
  Future<bool> deleteCurrent() async {
    if (_disposed) return false;
    final id = _id;
    if (id == null || !_persisted) return false;
    // 先等在飞行的保存落地：否则迟到的保存会把下面的复位覆盖掉，
    // 让界面显示「原记录仍保留」，而记录其实已经删掉了。
    final pending = _saving;
    if (pending != null) {
      await pending;
    }
    // 正文非空时先落盘，免得删除把刚写的内容一起丢掉。
    // 正文为空时跳过落盘：保存会因为「正文不能为空」失败，
    // 但用户要的是把这条记录删掉，不该被针对保存的规则拦住。
    if (_content.trim().isNotEmpty && !await flush()) return false;
    try {
      await repository.softDelete(id);
    } catch (error) {
      debugPrint('删除失败：$error');
      // 防抖定时器还活着的话，1 秒后会触发 flush()，把「正文不能为空」
      // 这条与删除无关的文案盖上来。这里先把它掐掉。
      _timer?.cancel();
      _timer = null;
      // 删除错误单独走 [deleteError]：不占用保存的状态与错误字段，
      // 否则界面会同时显示「保存失败」和「重试保存」。
      _deleteError = '删除失败，这条记录仍在。';
      _notify();
      return false;
    }
    _timer?.cancel();
    _content = _savedContent = '';
    _id = _dayKey = null;
    _createdAt = null;
    _persisted = false;
    _error = null;
    _deleteError = null;
    _status = SaveStatus.empty;
    _notify();
    return true;
  }
```

配套的三个公开成员：

```dart
  /// 当前是否正在编辑一条已保存的条目。新记录没有可删除的对象。
  bool get canDelete => _persisted && _id != null;

  /// 当前编辑的、且已落库的条目 ID；新记录（或保存失败、从未落库）时为 null。
  String? get currentEntryId => _persisted ? _id : null;

  /// 删除失败的原因。为 null 表示没有删除错误。
  ///
  /// 与保存错误分开：界面若把删除失败复用成保存失败，会同时显示
  /// 「保存失败」和「重试保存」，与用户做的事自相矛盾。
  String? get deleteError => _deleteError;
```

`_deleteError` 在 `updateContent()`、`newEntry()`、`edit()` 里都要清掉——用户换了内容或换了条目，上一次的删除失败提示就不该留着。


- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter analyze && flutter test test/ui/entry_editor_controller_test.dart`
Expected: `analyze` 无问题；全部通过。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/ui/entry_editor_controller.dart client/test/ui/entry_editor_controller_test.dart
git commit -m "feat(F005):编辑器支持删除当前条目,let editor delete the current entry"
```

---

### Task 8: 回顾页长按删除与撤销

**Files:**
- Modify: `client/lib/src/ui/timeline_page.dart`
- Test: `client/test/ui/timeline_page_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `softDelete` / `restore`，Task 3 的仓储实现
- Produces: `TimelinePage` 长按条目弹出「编辑／删除」；删除后条目离开列表并给出「已移到回收站 · 撤销」提示

- [ ] **Step 1: 写失败的测试**

在 `client/test/ui/timeline_page_test.dart` 追加。既有文件用 `MaterialApp(home: Scaffold(body: TimelinePage(...)))` 的写法，沿用它：

```dart
  final created = DateTime.utc(2026, 10, 28, 8);

  Future<MemoryRepository> seed() async {
    final repo = MemoryRepository();
    await repo.save(
      Entry(
        id: 'a',
        content: '第一条记录',
        createdAt: created,
        updatedAt: created,
        dayKey: '2026-10-28',
      ),
    );
    return repo;
  }

  Future<void> showTimeline(WidgetTester tester, MemoryRepository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePage(repository: repo, onEdit: (_) {}, onStart: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('长按条目弹出编辑与删除菜单', (tester) async {
    final repo = await seed();
    await showTimeline(tester, repo);

    await tester.longPress(find.text('第一条记录'));
    await tester.pumpAndSettle();

    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('确认删除后条目离开列表并提示可撤销', (tester) async {
    final repo = await seed();
    await showTimeline(tester, repo);

    await tester.longPress(find.text('第一条记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // 确认对话框里有内容摘要
    expect(find.textContaining('第一条记录'), findsWidgets);
    await tester.tap(find.text('删除')); // 对话框里的确认按钮
    await tester.pumpAndSettle();

    expect(find.text('第一条记录'), findsNothing);
    expect(find.text('已移到回收站'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    expect(repo.entries['a']!.deletedAt, isNotNull);
  });

  testWidgets('撤销后条目回到列表', (tester) async {
    final repo = await seed();
    await showTimeline(tester, repo);

    await tester.longPress(find.text('第一条记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(find.text('第一条记录'), findsOneWidget);
    expect(repo.entries['a']!.deletedAt, isNull);
  });

  testWidgets('删除失败时条目仍在并给出失败提示', (tester) async {
    final repo = await seed();
    repo.failDelete = true;
    await showTimeline(tester, repo);

    await tester.longPress(find.text('第一条记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('第一条记录'), findsOneWidget);
    expect(find.textContaining('删除失败'), findsOneWidget);
  });
```

注意：底部弹窗里的「删除」与确认对话框里的「删除」文案相同。第一个 `tester.tap(find.text('删除'))` 点的是弹窗项，第二个点的是对话框按钮。若两个「删除」同时出现在组件树里导致 `findsOneWidget` 失败，给弹窗项和对话框按钮各加一个 `Key`（见 Step 3 的实现）并用 `find.byKey` 定位。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/ui/timeline_page_test.dart`
Expected: FAIL — 长按无反应，菜单不出现。

- [ ] **Step 3: 实现长按菜单与删除**

`client/lib/src/ui/timeline_page.dart`：

给 `ListTile` 加 `onLongPress`：

```dart
                          onTap: () => widget.onEdit(entry),
                          onLongPress: () => _showEntryActions(entry),
```

在 `_TimelinePageState` 里新增方法：

```dart
  /// 长按条目弹出的操作菜单。
  Future<void> _showEntryActions(Entry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('timeline-action-edit'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              key: const Key('timeline-action-delete'),
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      widget.onEdit(entry);
    } else if (action == 'delete') {
      await _deleteEntry(entry);
    }
  }

  /// 删除一条记录：确认后软删除，并给出撤销入口。
  Future<void> _deleteEntry(Entry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text(
          '${_snippet(entry.content)}\n\n删除后可在回收站找回。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('timeline-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.softDelete(entry.id);
    } catch (error) {
      debugPrint('删除失败：$error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败，这条记录仍在')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _entries.removeWhere((item) => item.id == entry.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已移到回收站'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => unawaited(_restoreEntry(entry)),
        ),
      ),
    );
  }

  /// 撤销删除：把条目放回列表。
  Future<void> _restoreEntry(Entry entry) async {
    try {
      await widget.repository.restore(entry.id);
    } catch (error) {
      debugPrint('恢复失败：$error');
      return;
    }
    if (!mounted) return;
    setState(() {
      _entries.insert(_insertPosition(entry), entry);
    });
  }

  /// 条目在列表中的插入位置：按创建时间倒序、同刻按 ID 倒序。
  int _insertPosition(Entry entry) {
    var index = 0;
    while (index < _entries.length) {
      final current = _entries[index];
      final time = current.createdAt.compareTo(entry.createdAt);
      if (time == 0) {
        if (current.id.compareTo(entry.id) <= 0) break;
      } else if (time < 0) {
        break;
      }
      index++;
    }
    return index;
  }

  /// 确认对话框里的内容摘要。
  String _snippet(String content) {
    final flat = content.replaceAll('\n', ' ').trim();
    return flat.length <= 20 ? flat : '${flat.substring(0, 20)}…';
  }
```

同时在该文件顶部加 `import 'dart:async';`（`unawaited` 需要）以及 `import 'package:flutter/foundation.dart';`（`debugPrint`）。若 `dart:async` 已在，忽略。

注意：删除后 `_hasMore` 不变，但 `_entries` 变短；下次 `_load()` 用 `_entries.lastOrNull` 作游标，被删条目已不在库中，不会被重新读回。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter analyze && flutter test test/ui/timeline_page_test.dart`
Expected: `analyze` 无问题；全部通过。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/ui/timeline_page.dart client/test/ui/timeline_page_test.dart
git commit -m "feat(F005):回顾页支持长按删除与撤销,add long press delete with undo in timeline"
```

---

### Task 9: 记录页删除按钮

**Files:**
- Modify: `client/lib/src/ui/home_page.dart`
- Test: `client/test/ui/app_test.dart`

**Interfaces:**
- Consumes: Task 7 的 `canDelete` / `currentEntryId` / `deleteCurrent`
- Produces: `HomePage` 写作区在编辑已有条目时显示「删除这条」；删除成功后编辑器复位并提示「已移到回收站 · 撤销」

- [ ] **Step 1: 写失败的测试**

在 `client/test/ui/app_test.dart` 追加。既有文件用 `JournalApp(repository: repo)`，沿用它：

```dart
  testWidgets('编辑已有条目时出现删除按钮，新记录时不出现', (tester) async {
    final repo = MemoryRepository();
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.text('删除这条'), findsNothing);

    // 先写一条并保存，再从回顾页点开它。
    await tester.enterText(find.byKey(const Key('entry-content')), '第一条记录');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一条记录'));
    await tester.pumpAndSettle();

    expect(find.text('删除这条'), findsOneWidget);
  });

  testWidgets('确认删除后编辑器复位并可撤销', (tester) async {
    final repo = MemoryRepository();
    await tester.pumpWidget(JournalApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-content')), '第一条记录');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一条记录'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除这条'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('已移到回收站'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    // 编辑器已复位成空白的新记录
    final field = tester.widget<TextField>(
      find.byKey(const Key('entry-content')),
    );
    expect(field.controller!.text, isEmpty);
    expect(repo.entries.values.single.deletedAt, isNotNull);
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/ui/app_test.dart`
Expected: FAIL — 「删除这条」按钮不存在。

- [ ] **Step 3: 实现**

`client/lib/src/ui/home_page.dart`：

在 `_composer` 的底部一行里，追加删除按钮（只在 `canDelete` 时出现）：

```dart
              if (_editor.canDelete)
                TextButton(
                  key: const Key('composer-delete'),
                  onPressed: _transitioning ? null : () => _deleteCurrentEntry(),
                  child: const Text('删除这条'),
                ),
```

并在 `_HomePageState` 里新增：

```dart
  /// 删除当前编辑的条目。确认后条目移入回收站，编辑器复位。
  Future<void> _deleteCurrentEntry() async {
    if (_transitioning) return;
    final id = _editor.currentEntryId;
    if (id == null) return;
    final content = _editor.content;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text(
          '${_snippet(content)}\n\n删除后可在回收站找回。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('composer-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _transitioning = true;
    });
    final deleted = await _editor.deleteCurrent();
    if (!mounted) return;
    setState(() {
      _transitioning = false;
    });
    if (!deleted) {
      // 删除失败用控制器给的删除错误文案，不要复用保存错误：
      // 界面上的「保存失败」和「重试保存」对删除来说都不对。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_editor.deleteError ?? '删除失败，这条记录仍在')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已移到回收站'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => unawaited(_undoDelete(id)),
        ),
      ),
    );
  }

  /// 撤销删除：把条目从回收站恢复回来。
  Future<void> _undoDelete(String id) async {
    try {
      await widget.repository.restore(id);
    } catch (error) {
      debugPrint('恢复失败：$error');
    }
  }

  /// 确认对话框里的内容摘要。
  String _snippet(String content) {
    final flat = content.replaceAll('\n', ' ').trim();
    return flat.length <= 20 ? flat : '${flat.substring(0, 20)}…';
  }
```

所需 import：`dart:async`（`unawaited`）、`package:flutter/foundation.dart`（`debugPrint`）。文件顶部若没有则补上。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter analyze && flutter test test/ui/app_test.dart`
Expected: `analyze` 无问题；全部通过。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/ui/home_page.dart client/test/ui/app_test.dart
git commit -m "feat(F005):记录页增加删除当前条目入口,add delete entry action to composer"
```

---

### Task 10: 回收站页

**Files:**
- Create: `client/lib/src/ui/trash_page.dart`
- Test: `client/test/ui/trash_page_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `listDeleted` / `restore` / `purge` / `purgeAll`
- Produces: `TrashPage({required LocalEntryRepository repository})` —— 回收站二级页

- [ ] **Step 1: 写失败的测试**

新建 `client/test/ui/trash_page_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/ui/trash_page.dart';

import '../support/memory_repository.dart';

void main() {
  late MemoryRepository repository;

  setUp(() async {
    repository = MemoryRepository();
    await repository.save(
      Entry(
        id: 'a',
        content: '写错了',
        createdAt: DateTime.utc(2026, 10, 28, 3),
        updatedAt: DateTime.utc(2026, 10, 28, 3),
        dayKey: '2026-10-28',
      ),
    );
    await repository.softDelete('a');
  });

  testWidgets('回收站列出已删除条目并显示删除时间', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TrashPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);
    expect(find.text('彻底删除'), findsOneWidget);
  });

  testWidgets('恢复后条目离开回收站', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsNothing);
    expect(repository.entries['a']!.deletedAt, isNull);
  });

  testWidgets('彻底删除需要确认，确认后条目消失', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('彻底删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('彻底删除').last);
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsNothing);
    expect(repository.entries.containsKey('a'), isFalse);
  });

  testWidgets('清空回收站会清掉全部已删除条目', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('清空回收站'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空').last);
    await tester.pumpAndSettle();

    expect(find.text('写错了'), findsNothing);
    expect(repository.entries.containsKey('a'), isFalse);
  });

  testWidgets('回收站为空时显示空状态', (tester) async {
    final empty = MemoryRepository();
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: empty)));
    await tester.pumpAndSettle();

    expect(find.textContaining('回收站是空的'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/ui/trash_page_test.dart`
Expected: FAIL — `trash_page.dart` 不存在。

- [ ] **Step 3: 实现回收站页**

新建 `client/lib/src/ui/trash_page.dart`：

```dart
import 'package:flutter/material.dart';

import '../domain/entry.dart';
import '../domain/local_entry_repository.dart';

/// 回收站：已删除的条目先放在这里，可以恢复，也可以彻底删除。
class TrashPage extends StatefulWidget {
  const TrashPage({super.key, required this.repository});

  final LocalEntryRepository repository;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  final _entries = <Entry>[];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final entries = await widget.repository.listDeleted();
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(entries);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _restore(Entry entry) async {
    try {
      await widget.repository.restore(entry.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('恢复失败，请重试')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _entries.removeWhere((item) => item.id == entry.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢复到回顾')),
    );
  }

  Future<void> _purge(Entry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('彻底删除这条记录？'),
        content: const Text('彻底删除后不能再恢复，也无法通过备份找回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('trash-purge-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.purge(entry.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('彻底删除失败，请重试')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _entries.removeWhere((item) => item.id == entry.id);
    });
  }

  Future<void> _purgeAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空回收站？'),
        content: const Text('回收站里的所有记录都会被彻底删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('trash-purge-all-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final count = await widget.repository.purgeAll();
      if (!mounted) return;
      setState(() {
        _entries.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清空 $count 条')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('清空失败，请重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('回收站'),
      actions: [
        if (_entries.isNotEmpty)
          TextButton(
            key: const Key('trash-purge-all'),
            onPressed: _purgeAll,
            child: const Text('清空回收站'),
          ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _failed
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('读取失败，请重试'),
                    TextButton(onPressed: _load, child: const Text('重新加载')),
                  ],
                ),
              )
            : _entries.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '回收站是空的。\n删除的记录会先放到这里，可以随时恢复。',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      final deletedAt = entry.deletedAt?.toLocal();
                      final stamp = deletedAt == null
                          ? ''
                          : '${deletedAt.year}-${deletedAt.month.toString().padLeft(2, '0')}-'
                              '${deletedAt.day.toString().padLeft(2, '0')} '
                              '${deletedAt.hour.toString().padLeft(2, '0')}:'
                              '${deletedAt.minute.toString().padLeft(2, '0')}';
                      return Card(
                        elevation: 0,
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          title: Text(
                            entry.content,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('删除于 $stamp'),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                key: Key('trash-restore-${entry.id}'),
                                onPressed: () => _restore(entry),
                                child: const Text('恢复'),
                              ),
                              TextButton(
                                key: Key('trash-purge-${entry.id}'),
                                onPressed: () => _purge(entry),
                                child: const Text('彻底删除'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
  );
}
```

注意：`ListTile` 的 `trailing` 用 `Row` 时宽度有限，必要时改成 `Column` 或把操作按钮放到 `subtitle`。若真机上按钮被挤压显示不全，改为在卡片下方放一整行按钮——**这一点在真机验收时确认**。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter analyze && flutter test test/ui/trash_page_test.dart`
Expected: `analyze` 无问题；5 项测试通过。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/ui/trash_page.dart client/test/ui/trash_page_test.dart
git commit -m "feat(F005):新增回收站页面,add trash page for deleted entries"
```

---

### Task 11: 「我的」页入口与本地数据说明

**Files:**
- Modify: `client/lib/src/ui/local_data_page.dart`
- Test: `client/test/ui/local_data_page_test.dart`

**Interfaces:**
- Consumes: Task 10 的 `TrashPage`
- Produces: 「我的」页新增「回收站」入口；本地数据说明补充删除与回收站行为

- [ ] **Step 1: 写失败的测试**

在 `client/test/ui/local_data_page_test.dart` 追加：

```dart
  testWidgets('我的页有回收站入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: LocalDataPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('回收站'), findsOneWidget);
  });

  testWidgets('点击回收站入口能打开回收站页', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: LocalDataPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('回收站'));
    await tester.pumpAndSettle();

    expect(find.text('回收站是空的。\n删除的记录会先放到这里，可以随时恢复。'),
        findsOneWidget);
  });

  testWidgets('本地数据说明提到删除与回收站', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: LocalDataPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('本地数据说明'));
    await tester.pumpAndSettle();

    final note = tester.widget<Text>(
      find.byKey(const Key('local-data-note')),
    );
    expect(note.data, contains('回收站'));
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/ui/local_data_page_test.dart`
Expected: FAIL — 没有「回收站」入口，说明文案里也没有「回收站」。

- [ ] **Step 3: 实现**

`client/lib/src/ui/local_data_page.dart`：

在「导出与备份」入口之后插入：

```dart
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.delete_outline),
        title: const Text('回收站'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => TrashPage(repository: repository),
          ),
        ),
      ),
```

并把「本地数据说明」文案补上删除与回收站：

```dart
                  '当前版本保存日记正文和记录时间，使用应用内的本地数据库。\n\n'
                  '本版本不包含账号、应用内云同步、广告或行为统计，也不会申请麦克风、相机和相册权限。\n\n'
                  '看到“已保存”表示内容已写入本地数据库；尚未保存时强制终止应用可能丢失最近输入。\n\n'
                  '删除的记录会先放进回收站，可以随时恢复；在回收站里彻底删除或清空回收站后，'
                  '记录才真正从本机移除，届时无法通过备份找回。\n\n'
                  '在「导出与备份」里可以手动导出备份文件和 Markdown 文件，'
                  '两者都是明文、不做加密，任何文本编辑器都能打开，请自行保管。'
                  '应用不会自动备份，卸载应用或清除数据仍会丢失未导出的记录。',
```

并在文件顶部加 `import 'trash_page.dart';`。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter analyze && flutter test test/ui/local_data_page_test.dart`
Expected: `analyze` 无问题；全部通过。

- [ ] **Step 5: 提交**

```bash
git add client/lib/src/ui/local_data_page.dart client/test/ui/local_data_page_test.dart
git commit -m "feat(F005):我的页新增回收站入口并补充说明,add trash entry and update local data note"
```

---

### Task 12: 全量检查与构建

**Files:**
- 无（只跑检查，必要时修小问题）

**Interfaces:**
- Consumes: Task 1 ~ Task 11 的全部产出
- Produces: 静态分析干净、全部测试通过、调试 APK 可构建

- [ ] **Step 1: 静态分析**

Run: `cd client && flutter analyze`
Expected: `No issues found!`

若有 lint 问题（例如 `prefer_const_constructors`、未使用的 import），就地修掉。

- [ ] **Step 2: 全部测试**

Run: `cd client && flutter test`
Expected: 全部通过，**用例数不少于 91 + 本次新增**。把实际通过数记下来，测试报告要写真实数字。

- [ ] **Step 3: 构建调试 APK**

Run: `cd client && flutter build apk --debug`
Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`。

- [ ] **Step 3.5: 检查没有遗留的占位实现**

Task 1 曾在生产仓储里放 5 个 `UnimplementedError` 占位方法以便编译通过，Task 3 必须把它们全部替换掉。占位是**运行期**才炸的，`analyze` 和 `test` 都可能发现不了，所以这里单独做一次机械检查：

Run: `grep -rn "UnimplementedError" client/lib || echo "没有占位实现"`

Expected: 输出 `没有占位实现`。若仍有命中，说明 Task 3 漏了实现，必须回去补齐，不能继续合并。

- [ ] **Step 4: 提交（如有改动）**

```bash
git add -A
git commit -m "chore(F005):修复静态检查问题,fix analyzer warnings"
```

没有改动则跳过提交。

---

### Task 13: 真机验收与文档归档

**Files:**
- Create: `docs/test-reports/F005-删除记录与回收站测试报告-entry-delete-and-trash-test-report.md`
- Modify: `docs/features/README.md`
- Modify: `docs/features/F005-删除记录与回收站-entry-delete-and-trash.md`
- Modify: `docs/产品设计-product-design.md`
- Modify: `docs/test-reports/README.md`

**Interfaces:**
- Consumes: Task 12 的构建产物
- Produces: 测试报告、台账状态、产品设计同步

- [ ] **Step 1: 真机安装并验收**

用 `flutter build apk --debug` 产出的包在真机上安装，逐条走第 7 节的真机清单：

1. 回顾页长按一条记录 → 出现「编辑／删除」；选删除 → 确认对话框含内容摘要；确认后条目从时间轴消失，底部出现「已移到回收站 · 撤销」。
2. 点「撤销」→ 条目回到时间轴，位置和内容不变。
3. 再删一次 → 进入「我的 → 回收站」→ 能看到该条目、删除时间、「恢复」「彻底删除」。
4. 点「恢复」→ 条目回到时间轴，正文与创建时间不变。
5. 再删一次 → 回收站里「彻底删除」→ 确认 → 条目消失；杀进程重启，条目确实不在。
6. 记录页：编辑一条已有记录时出现「删除这条」；确认后编辑器复位为空白。
7. 导出备份 → 打开 JSON 文件 → 确认已删除条目带 `deletedAt`，`version` 为 2。
8. 用带 `deletedAt` 的备份导入 → 本地对应条目变为已删除。
9. 用一份 v1 旧备份导入 → 正常导入，不报错。
10. 飞行模式下上述删除与导出操作照常可用。

每条都记录实际结果。**没有实际执行的写「未执行」，不写成通过。**

- [ ] **Step 2: 写测试报告**

按 [测试报告模板](../../templates/测试报告模板-test-report-template.md) 创建 `docs/test-reports/F005-删除记录与回收站测试报告-entry-delete-and-trash-test-report.md`，写明被测版本、环境、命令与步骤、预期与实际、验收编号、失败项与未测范围。

- [ ] **Step 3: 同步台账与设计文档**

- `docs/features/README.md`：F005 状态推进到「待验收」或「已完成」，下一可用编号改为 `F006`。
- `docs/features/F005-删除记录与回收站-entry-delete-and-trash.md`：填第 8 节「实施变化与交付」，记录实际实现路径、实际检查命令、已知限制。
- `docs/产品设计-product-design.md`：补「删除采用软删除 + 回收站」这一决策与回收站不自动清理的限制。
- `docs/test-reports/README.md`：加入 F005 报告链接。

- [ ] **Step 4: 提交**

```bash
git add docs/
git commit -m "docs(F005):记录真机验收并同步台账,record device acceptance and update ledger"
```

- [ ] **Step 5: 合并**

合并前确认：静态分析干净、全部测试通过、报告与台账已更新。真机验收有阻塞项时**不得合并**，留在特性分支继续处理。

---

## 已知限制（写进报告与功能文档）

- 回收站不自动清理：已删除的条目一直留在本机，直到用户手动彻底删除或清空回收站。
- 回收站只列出最近 30 条，更早的条目不会出现在页面上（页面上有提示），但「清空回收站」会清掉全部。
- 回收站里的「撤销」只在当前会话有效；跨重启恢复靠回收站本身。
- **软删除**的条目不会被备份恢复复活（本次的核心承诺）：本地保留 `deleted_at` 墓碑，合并判定无条件跳过，代价是删除状态不会从旧备份里「解除」。
- **彻底删除**的条目没有墓碑：它从本机数据库物理移除，之后导出的备份不再包含它，**但导入彻底删除之前导出的旧备份时，这条记录仍会重新出现**。界面文案按此事实写明，不得宣称「彻底删除后无法通过备份找回」。
- 备份里的删除标记会随备份传播：把带删除标记的备份导入到新设备，那条记录在新设备上也是已删除状态。
- 本次不含云同步与账号，删除状态只在手动导出的备份文件里传播。
