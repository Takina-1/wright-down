import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/entry.dart';
import '../../domain/export/import_summary.dart';
import '../../domain/export/merge_decision.dart';
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
          version: 5,
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
              deleted_at INTEGER,
              mood TEXT,
              tags TEXT,
              photo BLOB
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
              // 迁移必须幂等：用户若用旧版打开过，列可能已经在了
              // （sqflite 在没有 onDowngrade 时只改 user_version，不改表结构）。
              // 撞名会让整库再也打不开。
              final columns = await db.rawQuery('PRAGMA table_info(entries)');
              final hasDeletedAt = columns.any((row) => row['name'] == 'deleted_at');
              if (!hasDeletedAt) {
                await db.execute(
                  'ALTER TABLE entries ADD COLUMN deleted_at INTEGER',
                );
              }
              await db.execute(
                'CREATE INDEX IF NOT EXISTS entries_deleted '
                'ON entries(deleted_at DESC, id DESC)',
              );
            }
            if (oldVersion < 3) {
              // F006 的 mood 迁移同样幂等：用户若用旧版打开过，列可能已在。
              final columns = await db.rawQuery('PRAGMA table_info(entries)');
              final hasMood = columns.any((row) => row['name'] == 'mood');
              if (!hasMood) {
                await db.execute('ALTER TABLE entries ADD COLUMN mood TEXT');
              }
            }
            if (oldVersion < 4) {
              // F009 的 tags 迁移同样幂等：用户若用旧版打开过，列可能已在。
              // tags 存 JSON 数组字符串（jsonEncode），读回时 jsonDecode，
              // 解码失败退回空列表（脏数据不崩）。
              final columns = await db.rawQuery('PRAGMA table_info(entries)');
              final hasTags = columns.any((row) => row['name'] == 'tags');
              if (!hasTags) {
                await db.execute('ALTER TABLE entries ADD COLUMN tags TEXT');
              }
            }
            if (oldVersion < 5) {
              // F010 的 photo 迁移同样幂等：用户若用旧版打开过，列可能已在。
              // photo 存照片原始字节（BLOB），读回时 toList() 成 Uint8List。
              final columns = await db.rawQuery('PRAGMA table_info(entries)');
              final hasPhoto = columns.any((row) => row['name'] == 'photo');
              if (!hasPhoto) {
                await db.execute('ALTER TABLE entries ADD COLUMN photo BLOB');
              }
            }
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
    final deletedAt = entry.deletedAt;
    final mood = entry.mood;
    // tags 存 JSON 数组字符串；空列表存 '[]'，避免 NULL 与空串混淆。
    final tagsJson = jsonEncode(entry.tags);
    // photo 存 BLOB：sqflite（平台实现与 FFI）都接受 Uint8List，直接传
    // 原始字节。null 即清除照片。不要用 toList()——FFI 不接受 List<int> 作 BLOB。
    final photo = entry.photo;
    await db.transaction((txn) async {
      final updated = await txn.update(
        'entries',
        {
          'content': entry.content,
          'updated_at': entry.updatedAt.millisecondsSinceEpoch,
          // 删除标记只在显式带上时才写：编辑一条已软删除的条目时，
          // 调用方构造的 Entry 不带 deletedAt，库里的删除标记必须留着，
          // 否则条目会被无声复活回到时间轴。
          if (deletedAt != null) 'deleted_at': deletedAt.millisecondsSinceEpoch,
          // mood 采用 always-write 口径：与 content/updated_at 一样总是写，
          // 传入 mood 为 null 即清除库中已有的心情（AC-07）。这与 deleted_at
          // 的「非空才写」不同——deleted_at 有 restore() 伴生清除（显式写
          // null），编辑正文时构造的 Entry 不带 deletedAt，若整体写 null 会
          // 无声复活条目；mood 没有这种伴生操作，靠 save 本身即可清除。
          'mood': mood,
          // tags 同样 always-write：传入空列表即清除库中已有标签。
          'tags': tagsJson,
          // photo 同样 always-write：传入 null 即清除库中已有照片。
          'photo': photo,
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
          if (deletedAt != null) 'deleted_at': deletedAt.millisecondsSinceEpoch,
          // mood 总是写：与 update 分支同口径，null 即不写心情。
          'mood': mood,
          'tags': tagsJson,
          // photo 总是写：与 update 分支同口径，null 即不写照片。
          'photo': photo,
        });
      }
    });
  }

  @override
  Future<List<Entry>> list({EntryCursor? before, String? tag, int limit = 30}) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    final db = await _database();
    // 标签存 JSON 数组字符串，用 instr 找引号包着的该标签（如 ["旅行","读书"]
    // 里找 "旅行"）。instr 是纯子串匹配，不解释通配符，标签含 % 或 _ 也不会
    // 误命中，无需转义。标签按原样匹配（大小写敏感，与 normalizeTags 一致）。
    final whereParts = <String>['deleted_at IS NULL'];
    final whereArgs = <Object?>[];
    if (before != null) {
      whereParts.add('(created_at < ? OR (created_at = ? AND id < ?))');
      whereArgs
        ..add(before.createdAt.millisecondsSinceEpoch)
        ..add(before.createdAt.millisecondsSinceEpoch)
        ..add(before.id);
    }
    if (tag != null && tag.isNotEmpty) {
      whereParts.add('instr(tags, ?) > 0');
      whereArgs.add('"$tag"');
    }
    final rows = await db.query(
      'entries',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
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
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'entries',
        columns: ['updated_at'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('No such entry: $id');
      }
      // 版本戳只许增不许减：设备时钟回拨时不能让 updated_at 倒退，
      // 否则旧备份会把刚恢复的条目打回删除状态。
      final current = rows.first['updated_at'] as int;
      final stamp = current > now ? current : now;
      // deleted_at 记的是删除发生的墙上时间，与版本戳分开。
      await txn.update(
        'entries',
        {'deleted_at': now, 'updated_at': stamp},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  @override
  Future<void> restore(String id) async {
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
    final db = await _database();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'entries',
        columns: ['updated_at', 'deleted_at'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      // 只对已删除的条目生效：未删除的条目没有可恢复的删除标记。
      if (rows.isEmpty || rows.first['deleted_at'] == null) {
        throw StateError('Entry $id is not in the trash');
      }
      // 版本戳只许增不许减：恢复时也不能把 updated_at 写小。
      final current = rows.first['updated_at'] as int;
      final stamp = current > now ? current : now;
      await txn.update(
        'entries',
        {'deleted_at': null, 'updated_at': stamp},
        where: 'id = ? AND deleted_at IS NOT NULL',
        whereArgs: [id],
      );
    });
  }

  @override
  Future<void> purge(String id) async {
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
    final db = await _database();
    // 只允许彻底删除回收站里的条目：活着条目误传 id 也不会被物理移除。
    final deleted = await db.delete(
      'entries',
      where: 'id = ? AND deleted_at IS NOT NULL',
      whereArgs: [id],
    );
    if (deleted == 0) {
      final rows = await db.query(
        'entries',
        columns: ['deleted_at'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('No such entry: $id');
      throw StateError('Entry $id is not in the trash');
    }
  }

  @override
  Future<int> purgeAll() async {
    final db = await _database();
    return db.delete('entries', where: 'deleted_at IS NOT NULL');
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
        // 判定规则与预览侧共用 [decideMerge]：预告的数字和实际写入的数字
        // 必须一致，包括「本地已删除的条目不会被备份复活」。
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
              // 插入时带上删除标记：备份里已删除的条目恢复后仍应留在回收站。
              'deleted_at': decision.entry.deletedAt?.millisecondsSinceEpoch,
              // 插入时带上心情：与 update 分支同口径，null 即不带心情。
              'mood': decision.entry.mood,
              // 插入时带上标签：存 JSON 数组字符串。
              'tags': jsonEncode(decision.entry.tags),
              // 插入时带上照片：存 BLOB（Uint8List），null 即不带照片。
              'photo': decision.entry.photo,
            });
            inserted++;
          case MergeAction.update:
            await txn.update(
              'entries',
              {
                'content': decision.entry.content,
                'updated_at': decision.entry.updatedAt.millisecondsSinceEpoch,
                // 删除状态跟备份走：备份带删除标记就把本地条目标记为已删除。
                // 「已删除的条目不被未删除的备份复活」由 decideMerge 的规则 2
                // 保证：本地已删除而备份未删除时根本走不到这个分支，
                // 所以这里写 null 只是保持列完整，不会取消删除标记。
                'deleted_at': decision.entry.deletedAt?.millisecondsSinceEpoch,
                // mood 跟 updatedAt 走：备份带 mood 用备份的，备份不带 mood 清空本地 mood。
                'mood': decision.entry.mood,
                // tags 跟 updatedAt 走：备份带标签用备份的，备份不带标签清空本地标签。
                'tags': jsonEncode(decision.entry.tags),
                // photo 跟 updatedAt 走：备份带照片用备份的，备份不带照片清空本地照片。
                'photo': decision.entry.photo,
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

  Entry _toEntry(Map<String, Object?> row) {
    final deletedAt = row['deleted_at'] as int?;
    final mood = row['mood'] as String?;
    // tags 存 JSON 数组字符串。解码失败（脏数据、旧库、手工改过的备份）
    // 退回空列表，不让回顾页崩溃——与 F004 对 dayKey 脏数据的口径一致。
    final tags = <String>[];
    final rawTags = row['tags'];
    if (rawTags is String && rawTags.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTags);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is String) tags.add(item);
          }
        }
      } catch (_) {
        // 解码失败留空，条目仍可显示。
      }
    }
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
      mood: mood,
      tags: tags,
      photo: _decodePhoto(row['photo']),
    );
  }

  /// 解码照片 BLOB。脏数据（非列表、空）退回 null，不让界面崩溃。
  ///
  /// 平台实现（Android）读回的是 `List<int>`，宿主 FFI 读回的是 `Uint8List`，
  /// 两者都转成 `Uint8List` 交给上层。
  Uint8List? _decodePhoto(Object? raw) {
    if (raw is Uint8List && raw.isNotEmpty) return raw;
    if (raw is List && raw.isNotEmpty) {
      return Uint8List.fromList(raw.map((v) => (v as num).toInt()).toList());
    }
    return null;
  }

  @override
  Future<void> close() async {
    final pending = _databaseFuture;
    _databaseFuture = null;
    if (pending != null) await (await pending).close();
  }
}
