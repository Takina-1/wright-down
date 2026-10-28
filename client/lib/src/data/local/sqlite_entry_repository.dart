import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/entry.dart';
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
    return rows
        .map(
          (row) => Entry(
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
          ),
        )
        .toList();
  }

  @override
  Future<void> close() async {
    final pending = _databaseFuture;
    _databaseFuture = null;
    if (pending != null) await (await pending).close();
  }
}
