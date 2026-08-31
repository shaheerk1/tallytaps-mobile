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
    itemCount: (map['itemCount'] as num?)?.toInt() ?? 0,
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
  bool get priceOverrideAllowed =>
      attributes['price_override_allowed'] == true ||
      attributes['price_override_allowed'] == 1;
  double get quantityStep =>
      (attributes['quantity_step'] as num?)?.toDouble() ?? 1;
  double get bagCharge => (attributes['bag_charge'] as num?)?.toDouble() ?? 0;
  double get wageCharge => (attributes['wage_charge'] as num?)?.toDouble() ?? 0;
  double? get minimumSellPrice =>
      (attributes['minimum_sell_price'] as num?)?.toDouble();
  double? get maximumSellPrice =>
      (attributes['maximum_sell_price'] as num?)?.toDouble();
  String get wageBasis => '${attributes['wage_basis'] ?? 'fixed'}';
  factory CatalogItem.fromApi(String nodeId, Map<String, dynamic> map) =>
      CatalogItem(
        nodeId: nodeId,
        sourceProductKey: '${map['sourceProductKey']}',
        name: '${map['name']}',
        sku: map['sku'] as String?,
        barcode: map['barcode'] as String?,
        category: map['category'] as String?,
        unit: map['unit'] as String?,
        unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0,
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
    unitPrice: (map['unit_price'] as num).toDouble(),
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
  });
  final CatalogItem item;
  double quantity;
  double? kilos;
  double? unitPriceOverride;
  double get unitPrice => unitPriceOverride ?? item.unitPrice;
  double get measure => item.pricingBasis == 'kilos' ? (kilos ?? 0) : quantity;
  double get merchandiseTotal => _money(unitPrice * measure);
  double get bagChargeTotal => _money(item.bagCharge * quantity);
  double get wageChargeTotal => _money(
    item.wageCharge *
        (item.wageBasis == 'kilos'
            ? (kilos ?? 0)
            : item.wageBasis == 'qty'
            ? quantity
            : 1),
  );
  double get lineTotal =>
      _money(merchandiseTotal + bagChargeTotal + wageChargeTotal);
  Map<String, Object?> toApi() => {
    'sourceProductKey': item.sourceProductKey,
    'sku': item.sku,
    'barcode': item.barcode,
    'description': item.name,
    'quantity': quantity,
    'kilos': kilos,
    'pricingBasis': item.pricingBasis,
    'unitPrice': unitPrice,
    'discount': 0,
    'tax': 0,
    'bagChargeTotal': bagChargeTotal,
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
  });
  final String clientBillId, catalogPosNodeId, deliveryScope, paymentMethod;
  final List<String> targetPosNodeIds;
  final List<MobileBillLine> lines;
  final DateTime createdAt;
  final String? customerName, customerMobile, note;
  bool synced;
  String? serverId;
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
}

double _money(double value) => (value * 100).round() / 100;
