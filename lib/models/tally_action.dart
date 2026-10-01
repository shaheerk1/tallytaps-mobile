import 'dart:convert';

import 'media_attachment.dart';

/// How a note is filed once it is written. The person writing it never picks
/// this: it follows what they attached, so the shop's own filters and totals
/// keep working.
enum ActionType {
  cash,
  card,
  stock,
  note;

  String get label => switch (this) {
    ActionType.cash => 'Cash',
    ActionType.card => 'Card',
    ActionType.stock => 'Stock',
    ActionType.note => 'Note',
  };

  /// Wording used on the "incoming" side of the toggle.
  String get inLabel => switch (this) {
    ActionType.cash => 'Received',
    ActionType.card => 'Received',
    ActionType.stock => 'Incoming',
    ActionType.note => '',
  };

  /// Wording used on the "outgoing" side of the toggle.
  String get outLabel => switch (this) {
    ActionType.cash => 'Paid',
    ActionType.card => 'Paid',
    ActionType.stock => 'Outgoing',
    ActionType.note => '',
  };
}

enum ActionDirection { incoming, outgoing }

/// Tells "leave this field alone" apart from "set this field to null".
const Object _unset = Object();

/// A single recorded business action, e.g. "Cash received 12,500".
class TallyAction {
  TallyAction({
    this.id,
    required this.type,
    required this.direction,
    required this.amount,
    this.item,
    this.qty,
    this.unit,
    this.note,
    this.isDraft = false,
    this.who,
    List<String>? tags,
    this.needsDoing = false,
    this.resolvedAt,
    this.resolvedBy,
    this.productKey,
    this.baseQty,
    this.baseUnit,
    this.moneyMethod,
    this.voicePath,
    List<String>? imagePaths,
    List<MediaAttachment>? mediaAssets,
    required this.createdAt,
    this.synced = false,
    this.syncedAt,
  }) : imagePaths = imagePaths ?? [],
       tags = tags ?? const [],
       mediaAssets = mediaAssets ?? [];

  /// Finished, and so bound for the shop.
  bool get isFinal => !isDraft;

  /// Something is written on it, so it is worth keeping in the list.
  bool get hasContent =>
      (note != null && note!.trim().isNotEmpty) ||
      amount > 0 ||
      hasGoods ||
      voicePath != null ||
      imagePaths.isNotEmpty ||
      (who != null && who!.trim().isNotEmpty) ||
      tags.isNotEmpty;

  /// The first line, for a list of notes.
  String get headline {
    final text = note?.trim() ?? '';
    if (text.isEmpty) return title;
    final firstBreak = text.indexOf('\n');
    return firstBreak == -1 ? text : text.substring(0, firstBreak);
  }

  /// What is left of the note under its first line.
  String get body {
    final text = note?.trim() ?? '';
    final firstBreak = text.indexOf('\n');
    return firstBreak == -1 ? '' : text.substring(firstBreak + 1).trim();
  }

  /// Whether the shop has seen to it. Only meaningful when it asked to be done.
  bool get isDone => resolvedAt != null;

  /// Still waiting on somebody at the shop.
  bool get isWaiting => needsDoing && resolvedAt == null;

  bool get hasMoney => amount > 0;
  bool get hasGoods => (item != null && item!.trim().isNotEmpty) || qty != null;

  /// The same note, once the shop has seen to it.
  /// The same note with a few things changed, because a draft is written in
  /// pieces and each piece is saved as it is typed.
  TallyAction copyWith({
    ActionType? type,
    ActionDirection? direction,
    double? amount,
    Object? item = _unset,
    Object? qty = _unset,
    Object? unit = _unset,
    Object? note = _unset,
    bool? isDraft,
    Object? who = _unset,
    List<String>? tags,
    bool? needsDoing,
    Object? productKey = _unset,
    Object? baseQty = _unset,
    Object? baseUnit = _unset,
    Object? moneyMethod = _unset,
    Object? voicePath = _unset,
    List<String>? imagePaths,
    List<MediaAttachment>? mediaAssets,
  }) => TallyAction(
    id: id,
    type: type ?? this.type,
    direction: direction ?? this.direction,
    amount: amount ?? this.amount,
    item: item == _unset ? this.item : item as String?,
    qty: qty == _unset ? this.qty : qty as double?,
    unit: unit == _unset ? this.unit : unit as String?,
    note: note == _unset ? this.note : note as String?,
    isDraft: isDraft ?? this.isDraft,
    who: who == _unset ? this.who : who as String?,
    tags: tags ?? this.tags,
    needsDoing: needsDoing ?? this.needsDoing,
    resolvedAt: resolvedAt,
    resolvedBy: resolvedBy,
    productKey: productKey == _unset ? this.productKey : productKey as String?,
    baseQty: baseQty == _unset ? this.baseQty : baseQty as double?,
    baseUnit: baseUnit == _unset ? this.baseUnit : baseUnit as String?,
    moneyMethod: moneyMethod == _unset ? this.moneyMethod : moneyMethod as String?,
    voicePath: voicePath == _unset ? this.voicePath : voicePath as String?,
    imagePaths: imagePaths ?? this.imagePaths,
    mediaAssets: mediaAssets ?? this.mediaAssets,
    createdAt: createdAt,
    synced: synced,
    syncedAt: syncedAt,
  );

  TallyAction seenAtShop(DateTime at, String? by) => TallyAction(
    id: id,
    type: type,
    direction: direction,
    amount: amount,
    item: item,
    qty: qty,
    unit: unit,
    note: note,
    isDraft: isDraft,
    who: who,
    tags: tags,
    needsDoing: needsDoing,
    resolvedAt: at,
    resolvedBy: by,
    productKey: productKey,
    baseQty: baseQty,
    baseUnit: baseUnit,
    moneyMethod: moneyMethod,
    voicePath: voicePath,
    imagePaths: imagePaths,
    mediaAssets: mediaAssets,
    createdAt: createdAt,
    synced: synced,
    syncedAt: syncedAt,
  );

  /// What the note says about itself, in one line, for a list.
  String get marks => [
    if (who != null && who!.isNotEmpty) 'about $who',
    ...tags.map((tag) => '#$tag'),
  ].join(' · ');

  int? id;
  final ActionType type;
  final ActionDirection direction;

  /// Value in rupees (price). For stock this is the price and may be 0.
  final double amount;

  /// Stock: selected item name, e.g. "Potatoes".
  final String? item;

  /// Stock: quantity (kilos or pieces) recorded in one field.
  final double? qty;

  /// Stock: unit label for [qty], e.g. "Kg" or "Pcs".
  final String? unit;

  final String? note;

  /// Still being written, or finished and on its way to the shop. A draft is
  /// the person's own; nothing leaves the phone until they say it is done.
  final bool isDraft;

  /// Who the note is about: a supplier, a customer, a driver, anybody.
  final String? who;

  /// The writer's own words for finding it again.
  final List<String> tags;

  /// The note is asking for something to be done at the shop.
  final bool needsDoing;

  /// When somebody at the shop saw to it, once the shop says so.
  final DateTime? resolvedAt;
  final String? resolvedBy;

  /// Goods: the POS item this is about, and the second measure when it has one.
  final String? productKey;
  final double? baseQty;
  final String? baseUnit;

  /// Money: whether it was cash or card.
  final String? moneyMethod;

  final String? voicePath;
  final List<String> imagePaths;
  List<MediaAttachment> mediaAssets;
  final DateTime createdAt;
  bool synced;
  DateTime? syncedAt;

  bool get hasMedia => voicePath != null || imagePaths.isNotEmpty || mediaAssets.isNotEmpty;

  String get title => switch (type) {
    ActionType.note => 'Note',
    ActionType.stock =>
      'Stock ${direction == ActionDirection.incoming ? 'in' : 'out'}'
          '$_itemLabel',
    _ =>
      '${type.label} ${direction == ActionDirection.incoming ? type.inLabel : type.outLabel}',
  };

  String get _itemLabel {
    final name = item;
    if (name == null || name.trim().isEmpty) return '';
    return ' · $name';
  }

  String get qtyLabel {
    final q = qty;
    if (q == null) return '';
    return '${_trimQty(q)} ${unit ?? ''}'.trim();
  }

  static List<String> _tagsOf(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {
      // A note is worth more than its tags; unreadable ones are dropped.
    }
    return const [];
  }

  static String _trimQty(double q) {
    final s = q.toStringAsFixed(2);
    if (s.endsWith('.00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) return s.substring(0, s.length - 1);
    return s;
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'type': type.name,
    'direction': direction.name,
    'amount': amount,
    'item': item,
    'qty': qty,
    'unit': unit,
    'note': note,
    'status': isDraft ? 'draft' : 'final',
    'who': who,
    'tags': tags.isEmpty ? null : jsonEncode(tags),
    'needs_doing': needsDoing ? 1 : 0,
    'resolved_at': resolvedAt?.millisecondsSinceEpoch,
    'resolved_by': resolvedBy,
    'product_key': productKey,
    'base_qty': baseQty,
    'base_unit': baseUnit,
    'money_method': moneyMethod,
    'voice_path': voicePath,
    'image_paths': imagePaths.isEmpty ? null : jsonEncode(imagePaths),
    'media_assets': mediaAssets.isEmpty
        ? null
        : jsonEncode(mediaAssets.map((asset) => asset.toMap()).toList()),
    'created_at': createdAt.millisecondsSinceEpoch,
    'synced': synced ? 1 : 0,
    'synced_at': syncedAt?.millisecondsSinceEpoch,
  };

  factory TallyAction.fromMap(Map<String, Object?> map) {
    List<String> images = const [];
    List<MediaAttachment> mediaAssets = const [];
    final rawImages = map['image_paths'];
    if (rawImages is String && rawImages.isNotEmpty) {
      final decoded = jsonDecode(rawImages);
      if (decoded is List) {
        images = decoded.whereType<String>().toList();
      }
    }
    final rawMedia = map['media_assets'];
    if (rawMedia is String && rawMedia.isNotEmpty) {
      final decoded = jsonDecode(rawMedia);
      if (decoded is List) {
        mediaAssets = decoded
            .whereType<Map>()
            .map((item) => MediaAttachment.fromMap(Map<String, Object?>.from(item)))
            .where((asset) => asset.clientMediaId.isNotEmpty && asset.localPath.isNotEmpty)
            .toList();
      }
    }
    return TallyAction(
      id: map['id'] as int?,
      type: ActionType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => ActionType.note,
      ),
      direction: ActionDirection.values.firstWhere(
        (d) => d.name == map['direction'],
        orElse: () => ActionDirection.incoming,
      ),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      item: map['item'] as String?,
      qty: (map['qty'] as num?)?.toDouble(),
      unit: map['unit'] as String?,
      note: map['note'] as String?,
      isDraft: (map['status'] as String?) == 'draft',
      who: map['who'] as String?,
      tags: _tagsOf(map['tags']),
      needsDoing: (map['needs_doing'] as num?) == 1,
      resolvedAt: map['resolved_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((map['resolved_at'] as num).toInt()),
      resolvedBy: map['resolved_by'] as String?,
      productKey: map['product_key'] as String?,
      baseQty: (map['base_qty'] as num?)?.toDouble(),
      baseUnit: map['base_unit'] as String?,
      moneyMethod: map['money_method'] as String?,
      voicePath: map['voice_path'] as String?,
      imagePaths: images,
      mediaAssets: mediaAssets,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as num?)?.toInt() ?? 0,
      ),
      synced: (map['synced'] as num?) == 1,
      syncedAt: map['synced_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['synced_at'] as int)
          : null,
    );
  }
}
