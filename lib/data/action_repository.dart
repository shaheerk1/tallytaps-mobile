import 'package:sqflite/sqflite.dart';

import '../models/tally_action.dart';
import 'app_database.dart';

/// Reads and writes recorded actions in local sqlite storage.
class ActionRepository {
  Future<int> insert(TallyAction action) async {
    final db = await AppDatabase.instance.database;
    return db.insert('actions', action.toMap());
  }

  Future<List<TallyAction>> getAll() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('actions', orderBy: 'created_at DESC');
    return rows.map(TallyAction.fromMap).toList();
  }

  Future<int> delete(int id) async {
    final db = await AppDatabase.instance.database;
    return db.delete('actions', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> markSynced(int id, DateTime syncedAt) async {
    final db = await AppDatabase.instance.database;
    return db.update(
      'actions',
      {'synced': 1, 'synced_at': syncedAt.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateMediaAssets(TallyAction action) async {
    if (action.id == null) return 0;
    final db = await AppDatabase.instance.database;
    return db.update(
      'actions',
      {'media_assets': action.toMap()['media_assets']},
      where: 'id = ?',
      whereArgs: [action.id],
    );
  }

  /// Stock items for the searchable item picker, sorted case-insensitively.
  Future<List<String>> getItems() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('items', orderBy: 'name COLLATE NOCASE');
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Adds a stock item (ignored if it already exists). Returns the name.
  Future<String> addItem(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final db = await AppDatabase.instance.database;
    await db.insert('items', {
      'name': trimmed,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return trimmed;
  }

  /// Sums of incoming and outgoing amounts created today (midnight onwards).
  Future<(double incoming, double outgoing)> todayTotals() async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final rows = await db.rawQuery(
      'SELECT direction, SUM(amount) AS total '
      'FROM actions WHERE created_at >= ? GROUP BY direction',
      [startOfDay.millisecondsSinceEpoch],
    );
    var incoming = 0.0;
    var outgoing = 0.0;
    for (final row in rows) {
      final total = (row['total'] as num?)?.toDouble() ?? 0;
      if (row['direction'] == ActionDirection.incoming.name) {
        incoming = total;
      } else {
        outgoing = total;
      }
    }
    return (incoming, outgoing);
  }
}
