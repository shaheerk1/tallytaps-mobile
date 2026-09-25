import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/tally_action.dart';
import 'app_database.dart';

/// A half-finished entry, kept so leaving the screen does not lose it.
///
/// One per kind of record: the cash screen, the card screen, the stock screen
/// and the note screen each keep their own. Photos and voice notes are already
/// files on the phone, so only their paths are kept here.
class EntryDraft {
  const EntryDraft({
    required this.type,
    required this.direction,
    this.input = '',
    this.note = '',
    this.item,
    this.qtyInput = '',
    this.priceInput = '',
    this.stockPriceMode = false,
    this.unit = 'Kg',
    this.voicePath,
    this.imagePaths = const [],
    required this.updatedAt,
  });

  final ActionType type;
  final ActionDirection direction;
  final String input;
  final String note;
  final String? item;
  final String qtyInput;
  final String priceInput;
  final bool stockPriceMode;
  final String unit;
  final String? voicePath;
  final List<String> imagePaths;
  final DateTime updatedAt;

  /// Nothing worth keeping: an empty screen should not leave a draft behind.
  bool get isEmpty =>
      input.trim().isEmpty &&
      note.trim().isEmpty &&
      (item == null || item!.trim().isEmpty) &&
      qtyInput.trim().isEmpty &&
      priceInput.trim().isEmpty &&
      voicePath == null &&
      imagePaths.isEmpty;

  Map<String, Object?> toMap() => {
    'type': type.name,
    'direction': direction.name,
    'input': input,
    'note': note,
    'item': item,
    'qty_input': qtyInput,
    'price_input': priceInput,
    'stock_price_mode': stockPriceMode ? 1 : 0,
    'unit': unit,
    'voice_path': voicePath,
    'image_paths': jsonEncode(imagePaths),
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory EntryDraft.fromMap(Map<String, Object?> map) => EntryDraft(
    type: ActionType.values.firstWhere(
      (value) => value.name == map['type'],
      orElse: () => ActionType.cash,
    ),
    direction: ActionDirection.values.firstWhere(
      (value) => value.name == map['direction'],
      orElse: () => ActionDirection.incoming,
    ),
    input: (map['input'] as String?) ?? '',
    note: (map['note'] as String?) ?? '',
    item: map['item'] as String?,
    qtyInput: (map['qty_input'] as String?) ?? '',
    priceInput: (map['price_input'] as String?) ?? '',
    stockPriceMode: (map['stock_price_mode'] as int? ?? 0) == 1,
    unit: (map['unit'] as String?) ?? 'Kg',
    voicePath: map['voice_path'] as String?,
    imagePaths: _paths(map['image_paths']),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (map['updated_at'] as int?) ?? 0,
    ),
  );

  static List<String> _paths(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((value) => '$value').toList();
    } catch (_) {
      // A draft is a convenience; unreadable ones are simply dropped.
    }
    return const [];
  }
}

/// Keeps one unfinished entry per kind of record, in the phone's own storage.
///
/// A draft is a convenience, never a reason to stop: if storage cannot be
/// reached the screen carries on as though there were no draft.
class EntryDraftRepository {
  static const _table = 'entry_drafts';

  Future<void> save(EntryDraft draft) async {
    if (draft.isEmpty) {
      await clear(draft.type);
      return;
    }
    try {
      final db = await AppDatabase.instance.database;
      await db.insert(
        _table,
        draft.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Nothing to do: the entry stays on screen either way.
    }
  }

  Future<EntryDraft?> load(ActionType type) async {
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query(
        _table,
        where: 'type = ?',
        whereArgs: [type.name],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final draft = EntryDraft.fromMap(rows.first);
      return draft.isEmpty ? null : draft;
    } catch (_) {
      return null;
    }
  }

  /// Which kinds of record have something unfinished, for the home screen.
  Future<Set<ActionType>> pendingTypes() async {
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query(_table, columns: ['type']);
      return rows
          .map(
            (row) => ActionType.values.firstWhere(
              (value) => value.name == row['type'],
              orElse: () => ActionType.cash,
            ),
          )
          .toSet();
    } catch (_) {
      return <ActionType>{};
    }
  }

  Future<void> clear(ActionType type) async {
    try {
      final db = await AppDatabase.instance.database;
      await db.delete(_table, where: 'type = ?', whereArgs: [type.name]);
    } catch (_) {
      // Same again: losing a draft must never block recording.
    }
  }
}
