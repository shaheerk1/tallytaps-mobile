import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/mobile_bill.dart';
import 'app_database.dart';

class BillingRepository {
  Future<void> replaceNodes(List<PosCatalogNode> nodes) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete('pos_catalog_nodes');
      for (final node in nodes) {
        await txn.insert('pos_catalog_nodes', node.toMap());
      }
    });
  }

  Future<List<PosCatalogNode>> nodes() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'pos_catalog_nodes',
      orderBy: 'nickname COLLATE NOCASE',
    );
    return rows
        .map(
          (r) => PosCatalogNode(
            id: r['id'] as String,
            nickname: r['nickname'] as String,
            itemCount: (r['item_count'] as num).toInt(),
            catalogUpdatedAt: r['catalog_updated_at'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    r['catalog_updated_at'] as int,
                  ),
          ),
        )
        .toList();
  }

  Future<void> replaceCatalog(String nodeId, List<CatalogItem> items) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'pos_catalog_items',
        where: 'node_id=?',
        whereArgs: [nodeId],
      );
      for (final item in items) {
        await txn.insert(
          'pos_catalog_items',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<CatalogItem>> catalog(String nodeId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'pos_catalog_items',
      where: 'node_id=?',
      whereArgs: [nodeId],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(CatalogItem.fromDb).toList();
  }

  Future<void> saveBill(MobileBill bill) async {
    final db = await AppDatabase.instance.database;
    await db.insert('mobile_bills', {
      'client_bill_id': bill.clientBillId,
      'catalog_node_id': bill.catalogPosNodeId,
      'payload': jsonEncode(bill.toApi()),
      'created_at': bill.createdAt.millisecondsSinceEpoch,
      'synced': bill.synced ? 1 : 0,
      'server_id': bill.serverId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markBillSynced(String clientBillId, String serverId) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'mobile_bills',
      {'synced': 1, 'server_id': serverId, 'last_error': null},
      where: 'client_bill_id=?',
      whereArgs: [clientBillId],
    );
  }

  Future<void> markBillError(String clientBillId, String error) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'mobile_bills',
      {'last_error': error},
      where: 'client_bill_id=?',
      whereArgs: [clientBillId],
    );
  }

  Future<List<Map<String, dynamic>>> pendingBills() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'mobile_bills',
      where: 'synced=0',
      orderBy: 'created_at',
    );
    return rows
        .map(
          (r) => Map<String, dynamic>.from(
            jsonDecode(r['payload'] as String) as Map,
          ),
        )
        .toList();
  }

  Future<List<MobileBill>> bills() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('mobile_bills', orderBy: 'created_at DESC');
    return rows.map((row) {
      final payload = Map<String, dynamic>.from(
        jsonDecode(row['payload'] as String) as Map,
      );
      return MobileBill.fromApi(
        payload,
        synced: (row['synced'] as num).toInt() == 1,
        serverId: row['server_id'] as String?,
        lastError: row['last_error'] as String?,
      );
    }).toList();
  }

  Future<int> pendingCount() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) count FROM mobile_bills WHERE synced=0',
    );
    return (rows.first['count'] as num).toInt();
  }
}
