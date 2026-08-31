import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Single sqlite connection used by the whole app.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'tally.db';
  static const _dbVersion = 4;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, _dbName),
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createActions(db);
    await _createItems(db);
    await _createBilling(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      for (final statement in const [
        'ALTER TABLE actions ADD COLUMN item TEXT',
        'ALTER TABLE actions ADD COLUMN qty REAL',
        'ALTER TABLE actions ADD COLUMN unit TEXT',
      ]) {
        await db.execute(statement);
      }
      await _createItems(db);
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE actions ADD COLUMN media_assets TEXT');
    }
    if (oldVersion < 4) await _createBilling(db);
  }

  Future<void> _createActions(Database db) async {
    await db.execute('''
      CREATE TABLE actions (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        type        TEXT    NOT NULL,
        direction   TEXT    NOT NULL,
        amount      REAL    NOT NULL DEFAULT 0,
        item        TEXT,
        qty         REAL,
        unit        TEXT,
        note        TEXT,
        voice_path  TEXT,
        image_paths TEXT,
        media_assets TEXT,
        created_at  INTEGER NOT NULL,
        synced      INTEGER NOT NULL DEFAULT 0,
        synced_at   INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_actions_created ON actions (created_at DESC)',
    );
  }

  Future<void> _createItems(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS items (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');
    for (final name in _defaultItems) {
      await db.insert('items', {
        'name': name,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _createBilling(Database db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS pos_catalog_nodes (id TEXT PRIMARY KEY,nickname TEXT NOT NULL,item_count INTEGER NOT NULL DEFAULT 0,catalog_updated_at INTEGER)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS pos_catalog_items (node_id TEXT NOT NULL,source_product_key TEXT NOT NULL,name TEXT NOT NULL,sku TEXT,barcode TEXT,category TEXT,unit TEXT,unit_price REAL NOT NULL,attributes TEXT NOT NULL,PRIMARY KEY(node_id,source_product_key))''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pos_catalog_items_name ON pos_catalog_items(node_id,name COLLATE NOCASE)',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS mobile_bills (client_bill_id TEXT PRIMARY KEY,catalog_node_id TEXT NOT NULL,payload TEXT NOT NULL,created_at INTEGER NOT NULL,synced INTEGER NOT NULL DEFAULT 0,server_id TEXT,last_error TEXT)''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_mobile_bills_pending ON mobile_bills(synced,created_at)',
    );
  }

  static const _defaultItems = [
    'Rice',
    'Dhal',
    'Sugar',
    'Flour',
    'Coconut Oil',
    'Potatoes',
    'Onions',
    'Green Chillies',
    'Milk Powder',
    'Tea Leaves',
    'Eggs',
    'Noodles',
    'Soap',
    'Salt',
  ];
}
