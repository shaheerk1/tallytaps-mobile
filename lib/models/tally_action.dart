import 'dart:convert';

import 'media_attachment.dart';

/// The four kinds of quick business action a stakeholder can record.
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
    this.voicePath,
    List<String>? imagePaths,
    List<MediaAttachment>? mediaAssets,
    required this.createdAt,
    this.synced = false,
    this.syncedAt,
  }) : imagePaths = imagePaths ?? [],
       mediaAssets = mediaAssets ?? [];

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
