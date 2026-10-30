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
    // 只对已删除的条目生效：未删除的条目没有可恢复的删除标记。
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
    // 不限制是否已删除：删除标记由调用方限定在回收站页。
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

  @override
  Future<void> close() async {
    final pending = _databaseFuture;
    _databaseFuture = null;
    if (pending != null) await (await pending).close();
  }
}
