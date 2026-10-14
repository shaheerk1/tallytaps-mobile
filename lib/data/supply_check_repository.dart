import 'package:sqflite/sqflite.dart';

import '../monitor/supply_check_models.dart';
import 'app_database.dart';

/// Supply checks kept on this phone.
///
/// Nothing here reaches the host. A check is one person's working out --
/// which lines they believe belong to a supply, at what commission -- and the
/// POS holds the real statements. Keeping them local also means the same lines
/// can be used again in another check, which is the point: one day's goods are
/// often looked at twice, from two different angles.
class SupplyCheckRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  Future<void> save(SavedSupplyCheck check) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert(
        'supply_checks',
        check.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('supply_check_lines', where: 'check_id = ?', whereArgs: [check.id]);
      final batch = txn.batch();
      for (final line in check.lines) {
        batch.insert(
          'supply_check_lines',
          {'check_id': check.id, 'line_id': line.id},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<SavedSupplyCheck>> list() async {
    final db = await _db;
    final rows = await db.query('supply_checks', orderBy: 'created_at DESC', limit: 200);
    return rows.map(SavedSupplyCheck.fromRow).toList();
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('supply_checks', where: 'id = ?', whereArgs: [id]);
      await txn.delete('supply_check_lines', where: 'check_id = ?', whereArgs: [id]);
    });
  }

  /// How many saved checks already used each of these lines.
  ///
  /// A line is never locked -- it may belong to two checks on purpose -- so this
  /// is said quietly beside the line rather than used to stop anything.
  Future<Map<String, int>> usage(Iterable<String> lineIds) async {
    final ids = lineIds.toSet().toList();
    if (ids.isEmpty) return {};
    final db = await _db;
    final counts = <String, int>{};
    // Sqlite takes a limited number of variables, so this goes in batches.
    for (var start = 0; start < ids.length; start += 400) {
      final slice = ids.sublist(start, start + 400 > ids.length ? ids.length : start + 400);
      final rows = await db.rawQuery(
        'SELECT line_id, COUNT(DISTINCT check_id) AS uses FROM supply_check_lines '
        'WHERE line_id IN (${List.filled(slice.length, '?').join(',')}) GROUP BY line_id',
        slice,
      );
      for (final row in rows) {
        counts['${row['line_id']}'] = (row['uses'] as num?)?.toInt() ?? 0;
      }
    }
    return counts;
  }
}
