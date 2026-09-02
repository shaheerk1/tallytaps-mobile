import 'dart:convert';

class PosCatalogNode {
  const PosCatalogNode({
    required this.id,
    required this.nickname,
    required this.itemCount,
    this.catalogUpdatedAt,
  });
  final String id;
  final String nickname;
  final int itemCount;
  final DateTime? catalogUpdatedAt;
  factory PosCatalogNode.fromMap(Map<String, dynamic> map) => PosCatalogNode(
    id: '${map['id']}',
    nickname: (map['nickname'] as String?)?.trim().isNotEmpty == true
        ? map['nickname']
        : 'POS catalog',
    itemCount: _asInt(map['itemCount']),
    catalogUpdatedAt: DateTime.tryParse('${map['catalogUpdatedAt'] ?? ''}'),
  );
  Map<String, Object?> toMap() => {
    'id': id,
    'nickname': nickname,
    'item_count': itemCount,
    'catalog_updated_at': catalogUpdatedAt?.millisecondsSinceEpoch,
  };
}

class CatalogItem {
  const CatalogItem({
    required this.nodeId,
    required this.sourceProductKey,
    required this.name,
    required this.unitPrice,
    required this.attributes,
    this.sku,
    this.barcode,
    this.category,
    this.unit,
  });
  final String nodeId, sourceProductKey, name;
  final String? sku, barcode, category, unit;
  final double unitPrice;
  final Map<String, dynamic> attributes;
  String get pricingBasis =>
      attributes['pricing_basis'] == 'kilos' ? 'kilos' : 'qty';
  String get handlingUom =>
      _asText(attributes['handling_uom']) ?? _asText(unit) ?? 'unit';
  String? get baseUom =>
      _asText(attributes['base_uom']) ??
      (requiresMeasuredQuantity ? _asText(unit) ?? 'measured unit' : null);
  bool get dualUomEnabled => _asBool(attributes['dual_uom_enabled']);
  bool get requiresMeasuredQuantity =>
      dualUomEnabled ||
      pricingBasis == 'kilos' ||
      _asBool(attributes['requires_kilos']);
  bool get allowZeroQuantity => _asBool(attributes['allow_zero_quantity']);
  bool get priceOverrideAllowed =>
      _asBool(attributes['price_override_allowed']);
  bool get priceOverrideReasonRequired =>
      _asBool(attributes['price_override_reason_required']);
  double get quantityStep => _asDouble(attributes['quantity_step']) ?? 1;
  double get bagCharge => _asDouble(attributes['bag_charge']) ?? 0;
  double get wageCharge => _asDouble(attributes['wage_charge']) ?? 0;
  double? get minimumSellPrice => _asDouble(attributes['minimum_sell_price']);
  double? get maximumSellPrice => _asDouble(attributes['maximum_sell_price']);
  String get wageBasis {
    final value = _asText(attributes['wage_basis']) ?? 'none';
    return const {'qty', 'kilos'}.contains(value) ? value : 'none';
  }

  String get priceUom =>
      pricingBasis == 'kilos' ? baseUom ?? 'measured unit' : handlingUom;
  factory CatalogItem.fromApi(String nodeId, Map<String, dynamic> map) =>
      CatalogItem(
        nodeId: nodeId,
        sourceProductKey: '${map['sourceProductKey']}',
        name: '${map['name']}',
        sku: map['sku'] as String?,
        barcode: map['barcode'] as String?,
        category: map['category'] as String?,
        unit: map['unit'] as String?,
        unitPrice: _asDouble(map['unitPrice']) ?? 0,
        attributes: Map<String, dynamic>.from(
          map['attributes'] is Map ? map['attributes'] as Map : {},
        ),
      );
  Map<String, Object?> toMap() => {
    'node_id': nodeId,
    'source_product_key': sourceProductKey,
    'name': name,
    'sku': sku,
    'barcode': barcode,
    'category': category,
    'unit': unit,
    'unit_price': unitPrice,
    'attributes': jsonEncode(attributes),
  };
  factory CatalogItem.fromDb(Map<String, Object?> map) => CatalogItem(
    nodeId: map['node_id'] as String,
    sourceProductKey: map['source_product_key'] as String,
    name: map['name'] as String,
    sku: map['sku'] as String?,
    barcode: map['barcode'] as String?,
    category: map['category'] as String?,
    unit: map['unit'] as String?,
    unitPrice: _asDouble(map['unit_price']) ?? 0,
    attributes: Map<String, dynamic>.from(
      jsonDecode(map['attributes'] as String) as Map,
    ),
  );
}

class MobileBillLine {
  MobileBillLine({
    required this.item,
    this.quantity = 1,
    this.kilos,
    this.unitPriceOverride,
    this.priceOverrideReason,
  });
  final CatalogItem item;
  double quantity;
  double? kilos;
  double? unitPriceOverride;
  String? priceOverrideReason;
  double get unitPrice => unitPriceOverride ?? item.unitPrice;
  double get measure => item.pricingBasis == 'kilos' ? (kilos ?? 0) : quantity;
  bool get hasPriceOverride =>
      unitPriceOverride != null &&
      (unitPriceOverride! - item.unitPrice).abs() >= .005;
  bool get isValid =>
      quantity >= 0 &&
      (item.allowZeroQuantity || quantity > 0) &&
      (!item.requiresMeasuredQuantity || (kilos ?? 0) > 0) &&
      measure > 0 &&
      (!item.priceOverrideReasonRequired ||
          !hasPriceOverride ||
          (priceOverrideReason?.trim().isNotEmpty ?? false));
  double get merchandiseTotal => _money(unitPrice * measure);
  double get bagChargeTotal => _money(item.bagCharge * quantity);
  double get wageChargeTotal => _money(
    item.wageCharge *
        (item.wageBasis == 'kilos'
            ? (kilos ?? 0)
            : item.wageBasis == 'qty'
            ? quantity
            : 0),
  );
  double get lineTotal =>
      _money(merchandiseTotal + bagChargeTotal + wageChargeTotal);

  factory MobileBillLine.fromApi(
    String catalogNodeId,
    Map<String, dynamic> map,
  ) {
    final snapshot = Map<String, dynamic>.from(
      map['productSnapshot'] is Map ? map['productSnapshot'] as Map : {},
    );
    snapshot.addAll({
      'pricing_basis': _asText(map['pricingBasis']) ?? 'qty',
      'handling_uom': _asText(map['handlingUom']),
      'base_uom': _asText(map['baseUom']),
      'dual_uom_enabled': map['dualUomEnabled'],
      'requires_kilos': map['requiresMeasuredQuantity'],
      'allow_zero_quantity': map['allowZeroQuantity'],
      'quantity_step': map['quantityStep'],
      'bag_charge': map['packagingChargeRate'] ?? map['bagChargeRate'],
      'wage_charge': map['wageChargeRate'],
      'wage_basis': map['wageBasis'],
      'price_override_allowed': map['priceOverrideAllowed'],
      'price_override_reason_required': map['priceOverrideReasonRequired'],
      'minimum_sell_price': map['minimumSellPrice'],
      'maximum_sell_price': map['maximumSellPrice'],
    });
    snapshot.removeWhere((_, value) => value == null);

    final chargedPrice = _asDouble(map['unitPrice']) ?? 0;
    final catalogPrice = _asDouble(map['catalogUnitPrice']) ?? chargedPrice;
    final item = CatalogItem(
      nodeId: catalogNodeId,
      sourceProductKey: '${map['sourceProductKey'] ?? ''}',
      name: _asText(map['description']) ?? 'Item',
      sku: _asText(map['sku']),
      barcode: _asText(map['barcode']),
      unit: _asText(map['baseUom']) ?? _asText(map['handlingUom']),
      unitPrice: catalogPrice,
      attributes: snapshot,
    );
    return MobileBillLine(
      item: item,
      quantity:
          _asDouble(map['handlingQuantity'] ?? map['quantity']) ?? 0,
      kilos: _asDouble(map['measuredQuantity'] ?? map['kilos']),
      unitPriceOverride:
          _asBool(map['priceOverrideApplied']) || chargedPrice != catalogPrice
          ? chargedPrice
          : null,
      priceOverrideReason: _asText(map['priceOverrideReason']),
    );
  }
  Map<String, Object?> toApi() => {
    'sourceProductKey': item.sourceProductKey,
    'sku': item.sku,
    'barcode': item.barcode,
    'description': item.name,
    'quantity': quantity,
    'kilos': kilos,
    'handlingQuantity': quantity,
    'measuredQuantity': kilos,
    'handlingUom': item.handlingUom,
    'baseUom': item.baseUom,
    'dualUomEnabled': item.dualUomEnabled,
    'requiresMeasuredQuantity': item.requiresMeasuredQuantity,
    'quantityStep': item.quantityStep,
    'allowZeroQuantity': item.allowZeroQuantity,
    'pricingBasis': item.pricingBasis,
    'unitPrice': unitPrice,
    'catalogUnitPrice': item.unitPrice,
    'priceOverrideApplied': hasPriceOverride,
    'priceOverrideAllowed': item.priceOverrideAllowed,
    'priceOverrideReasonRequired': item.priceOverrideReasonRequired,
    'minimumSellPrice': item.minimumSellPrice,
    'maximumSellPrice': item.maximumSellPrice,
    'priceOverrideReason': hasPriceOverride ? priceOverrideReason : null,
    'discount': 0,
    'tax': 0,
    'bagChargeRate': item.bagCharge,
    'packagingChargeRate': item.bagCharge,
    'bagChargeTotal': bagChargeTotal,
    'packagingChargeTotal': bagChargeTotal,
    'wageChargeRate': item.wageCharge,
    'wageBasis': item.wageBasis,
    'wageChargeTotal': wageChargeTotal,
    'lineTotal': lineTotal,
    'productSnapshot': item.attributes,
  };
}

class MobileBill {
  MobileBill({
    required this.clientBillId,
    required this.catalogPosNodeId,
    required this.deliveryScope,
    required this.targetPosNodeIds,
    required this.lines,
    required this.paymentMethod,
    required this.createdAt,
    this.customerName,
    this.customerMobile,
    this.note,
    this.synced = false,
    this.serverId,
    this.lastError,
  });
  final String clientBillId, catalogPosNodeId, deliveryScope, paymentMethod;
  final List<String> targetPosNodeIds;
  final List<MobileBillLine> lines;
  final DateTime createdAt;
  final String? customerName, customerMobile, note;
  bool synced;
  String? serverId, lastError;
  double get grandTotal =>
      _money(lines.fold(0, (sum, line) => sum + line.lineTotal));
  Map<String, Object?> toApi() => {
    'clientBillId': clientBillId,
    'catalogPosNodeId': catalogPosNodeId,
    'deliveryScope': deliveryScope,
    'targetPosNodeIds': targetPosNodeIds,
    'customerName': customerName,
    'customerMobile': customerMobile,
    'note': note,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'lines': lines.map((line) => line.toApi()).toList(),
    'payments': paymentMethod == 'unpaid'
        ? []
        : [
            {'method': paymentMethod, 'amount': grandTotal},
          ],
  };

  factory MobileBill.fromApi(
    Map<String, dynamic> map, {
    bool synced = false,
    String? serverId,
    String? lastError,
  }) {
    final catalogNodeId = '${map['catalogPosNodeId'] ?? ''}';
    final rawLines = map['lines'] is List ? map['lines'] as List : const [];
    final rawTargets = map['targetPosNodeIds'] is List
        ? map['targetPosNodeIds'] as List
        : const [];
    final payments = map['payments'] is List
        ? map['payments'] as List
        : const [];
    String paymentMethod = 'unpaid';
    if (payments.isNotEmpty && payments.first is Map) {
      paymentMethod =
          _asText((payments.first as Map)['method']) ?? paymentMethod;
    }
    return MobileBill(
      clientBillId: '${map['clientBillId'] ?? ''}',
      catalogPosNodeId: catalogNodeId,
      deliveryScope: _asText(map['deliveryScope']) ?? 'all',
      targetPosNodeIds: rawTargets.map((value) => '$value').toList(),
      customerName: _asText(map['customerName']),
      customerMobile: _asText(map['customerMobile']),
      note: _asText(map['note']),
      createdAt:
          DateTime.tryParse('${map['createdAt'] ?? ''}')?.toLocal() ??
          DateTime.now(),
      lines: rawLines
          .whereType<Map>()
          .map(
            (line) => MobileBillLine.fromApi(
              catalogNodeId,
              Map<String, dynamic>.from(line),
            ),
          )
          .toList(),
      paymentMethod: paymentMethod,
      synced: synced,
      serverId: serverId,
      lastError: lastError,
    );
  }
}

double _money(double value) => (value * 100).round() / 100;

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

int _asInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    return switch (value.trim().toLowerCase()) {
      'true' || '1' || 'yes' || 'on' => true,
      _ => false,
    };
  }
  return false;
}

String? _asText(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}
