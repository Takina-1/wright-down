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
          version: 6,
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
              photo BLOB,
              sync_stamps TEXT
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
            if (oldVersion < 6) {
              // F013 的 sync_stamps 迁移同样幂等：用户若用旧版打开过，列可能已在。
              // sync_stamps 存字段级同步时间戳 JSON（字段名→毫秒），读回时
              // jsonDecode，解码失败退回空 map（脏数据不崩）。
              final columns = await db.rawQuery('PRAGMA table_info(entries)');
              final hasStamps = columns.any((row) => row['name'] == 'sync_stamps');
              if (!hasStamps) {
                await db.execute('ALTER TABLE entries ADD COLUMN sync_stamps TEXT');
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
    // 字段级时间戳取 entry.updatedAt（逻辑更新时间），而非 DateTime.now()
    // （物理保存时间）。离线编辑时调用方把 updatedAt 设为编辑时刻，
    // 上线同步时另一设备可能已有更新的字段；用 updatedAt 打戳才能让
    // LWW 正确保留较新的字段，用 now 会让离线保存时间盖过较早的在线编辑。
    final now = entry.updatedAt.millisecondsSinceEpoch;
    // 读当前行：既要比较字段值是否变更（决定打哪些戳），也要拿旧 stamps
    // 保留未变更字段的时间戳。新建条目查不到行，content/mood/tags 全打 now。
    final rows = await db.query(
      'entries',
      where: 'id = ?',
      whereArgs: [entry.id],
      limit: 1,
    );
    final existing = rows.isEmpty ? null : _toEntry(rows.first);
    final stamps = _computeStamps(existing, entry, now);
    final stampsJson = jsonEncode(stamps);
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
          // sync_stamps 跟字段走：变更字段打 now，未变更字段保留旧戳，
          // deletedAt 由 softDelete/restore 维护，save 不碰。
          'sync_stamps': stampsJson,
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
          // 新建条目所有字段打 now。
          'sync_stamps': stampsJson,
        });
      }
    });
  }

  @override
  Future<void> saveMerged(Entry entry) async {
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
    // 版本戳只许增不许减：取 now 与 e.updatedAt 的较大者，设备时钟回拨时
    // 不让 updated_at 倒退。与 softDelete/restore 的口径一致。
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final stamp = entry.updatedAt.millisecondsSinceEpoch > now
        ? entry.updatedAt.millisecondsSinceEpoch
        : now;
    // sync_stamps 原样保留传入的字段级时间戳（jsonEncode，不重算）。
    // pull 合并后的条目字段时间戳取自远端 t，save 的 _computeStamps 会用
    // updatedAt 重算覆盖这些远端戳，破坏「字段最后同步时间」不变量（M-16）。
    final stampsJson = jsonEncode(entry.syncStamps);
    await db.transaction((txn) async {
      final updated = await txn.update(
        'entries',
        {
          'content': entry.content,
          'updated_at': stamp,
          // 删除标记只在显式带上时才写：与 save 同口径，编辑已软删除条目时
          // 库里的删除标记必须留着，否则条目会被无声复活回到时间轴。
          if (deletedAt != null) 'deleted_at': deletedAt.millisecondsSinceEpoch,
          // mood 采用 always-write 口径：与 save 同口径，传入 mood 为 null
          // 即清除库中已有的心情（AC-07）。
          'mood': mood,
          // tags 同样 always-write：传入空列表即清除库中已有标签。
          'tags': tagsJson,
          // photo 同样 always-write：传入 null 即清除库中已有照片。
          'photo': photo,
          // sync_stamps 原样保留调用方传入的字段级时间戳（pull 远端 t）。
          'sync_stamps': stampsJson,
        },
        where: 'id = ?',
        whereArgs: [entry.id],
      );
      if (updated == 0) {
        await txn.insert('entries', {
          'id': entry.id,
          'content': entry.content,
          'created_at': entry.createdAt.millisecondsSinceEpoch,
          'updated_at': stamp,
          'day_key': entry.dayKey,
          if (deletedAt != null) 'deleted_at': deletedAt.millisecondsSinceEpoch,
          // mood 总是写：与 update 分支同口径，null 即不写心情。
          'mood': mood,
          'tags': tagsJson,
          // photo 总是写：与 update 分支同口径，null 即不写照片。
          'photo': photo,
          // 新建条目的 sync_stamps 同样原样保留传入值（pull 新建走远端 t）。
          'sync_stamps': stampsJson,
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
        columns: ['updated_at', 'sync_stamps'],
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
      // sync_stamps['deletedAt'] 打 now：删除状态变更要传播到其他设备。
      final stamps = _decodeStamps(rows.first['sync_stamps']);
      stamps['deletedAt'] = now;
      await txn.update(
        'entries',
        {
          'deleted_at': now,
          'updated_at': stamp,
          'sync_stamps': jsonEncode(stamps),
        },
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
        columns: ['updated_at', 'deleted_at', 'sync_stamps'],
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
      // deleted_at 清除（写 null），但 sync_stamps['deletedAt'] 打 now：
      // 删除状态从「已删除」变回「未删除」，这个变更要传播到其他设备。
      final stamps = _decodeStamps(rows.first['sync_stamps']);
      stamps['deletedAt'] = now;
      await txn.update(
        'entries',
        {
          'deleted_at': null,
          'updated_at': stamp,
          'sync_stamps': jsonEncode(stamps),
        },
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
      syncStamps: _decodeStamps(row['sync_stamps']),
    );
  }

  /// 计算字段级同步时间戳。对已存在条目，只给值变更的字段打 now，未变更字段
  /// 保留旧戳；对新建条目，content/mood/tags 全部打 now。deletedAt 由
  /// softDelete/restore 维护，save 不碰。
  Map<String, int> _computeStamps(Entry? existing, Entry e, int now) {
    final old = existing?.syncStamps ?? const {};
    final stamps = <String, int>{...old};
    void bump(String field, Object? newV, Object? oldV) {
      if (newV != oldV) stamps[field] = now;
    }
    bump('content', e.content, existing?.content);
    bump('mood', e.mood, existing?.mood);
    bump('tags', e.tags, existing?.tags);
    return stamps;
  }

  /// 解码 sync_stamps JSON。脏数据（非字符串、空、非法 JSON）退回空 map，
  /// 不让界面崩溃——与 tags 解码口径一致。
  Map<String, int> _decodeStamps(Object? raw) {
    final stamps = <String, int>{};
    if (raw is String && raw.isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) {
          for (final e in d.entries) {
            if (e.value is int) stamps[e.key as String] = e.value as int;
          }
        }
      } catch (_) {
        // 解码失败留空，条目仍可显示。
      }
    }
    return stamps;
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
