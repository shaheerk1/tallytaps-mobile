import '../theme/app_theme.dart';

double _money(Object? value) => (value as num?)?.toDouble() ?? 0;
double? _optional(Object? value) => (value as num?)?.toDouble();
int _count(Object? value) => (value as num?)?.toInt() ?? 0;
String _text(Object? value, [String fallback = '']) =>
    value is String && value.isNotEmpty ? value : fallback;
String? _maybe(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
List<Map<String, dynamic>> _rows(Object? value) => value is List
    ? value.whereType<Map>().map((row) => row.cast<String, dynamic>()).toList()
    : const [];

/// A delivery note as the POS recorded it.
class MonitorGoodsReceipt {
  const MonitorGoodsReceipt({
    required this.grnId,
    required this.nodeId,
    required this.grnNumber,
    required this.status,
    required this.businessDate,
    required this.lineCount,
    required this.goodsValue,
    required this.ownershipModel,
    this.supplierName,
    this.supplierCode,
    this.vehicleNo,
    this.locCode,
  });

  final String grnId;
  final String nodeId;
  final String grnNumber;
  final String status;
  final String businessDate;
  final int lineCount;
  final double goodsValue;
  final String ownershipModel;
  final String? supplierName;
  final String? supplierCode;
  final String? vehicleNo;
  final String? locCode;

  bool get isDraft => status == 'draft';
  String get supplierLabel => supplierName ?? supplierCode ?? 'No supplier named';
  bool get isOwned => ownershipModel != 'consignment';

  factory MonitorGoodsReceipt.fromMap(Map<String, dynamic> map) => MonitorGoodsReceipt(
    grnId: _text(map['grnId']),
    nodeId: _text(map['nodeId']),
    grnNumber: _text(map['grnNumber'], 'Delivery note'),
    status: _text(map['status'], 'draft'),
    businessDate: _text(map['businessDate']),
    lineCount: _count(map['lineCount']),
    goodsValue: _money(map['goodsValue']),
    ownershipModel: _text(map['ownershipModel'], 'owned'),
    supplierName: _maybe(map['supplierName']),
    supplierCode: _maybe(map['supplierCode']),
    vehicleNo: _maybe(map['vehicleNo']),
    locCode: _maybe(map['locCode']),
  );
}

/// One line of a delivery note, in both measures.
class MonitorGoodsReceiptLine {
  const MonitorGoodsReceiptLine({
    required this.lineNo,
    required this.productName,
    required this.handlingQty,
    required this.handlingUom,
    required this.unitCost,
    required this.lineValue,
    this.baseQty,
    this.baseUom,
    this.itemCode,
  });

  final int lineNo;
  final String productName;
  final double handlingQty;
  final String handlingUom;
  final double unitCost;
  final double lineValue;
  final double? baseQty;
  final String? baseUom;
  final String? itemCode;

  factory MonitorGoodsReceiptLine.fromMap(Map<String, dynamic> map) => MonitorGoodsReceiptLine(
    lineNo: _count(map['lineNo']),
    productName: _text(map['productName'], 'Item'),
    handlingQty: _money(map['handlingQty']),
    handlingUom: _text(map['handlingUom'], 'qty'),
    unitCost: _money(map['unitCost']),
    lineValue: _money(map['lineValue']),
    baseQty: _optional(map['baseQty']),
    baseUom: _maybe(map['baseUom']),
    itemCode: _maybe(map['itemCode']),
  );
}

class MonitorGoodsReceiptDetail {
  const MonitorGoodsReceiptDetail({required this.grn, required this.lines});

  final MonitorGoodsReceipt grn;
  final List<MonitorGoodsReceiptLine> lines;

  double get total =>
      lines.fold<double>(0, (sum, line) => sum + line.lineValue);

  factory MonitorGoodsReceiptDetail.fromMap(Map<String, dynamic> map) {
    final head = (map['grn'] as Map?)?.cast<String, dynamic>() ?? {};
    return MonitorGoodsReceiptDetail(
      grn: MonitorGoodsReceipt.fromMap({...head, 'nodeId': map['nodeId']}),
      lines: _rows(map['lines']).map(MonitorGoodsReceiptLine.fromMap).toList(),
    );
  }
}

/// A lot of goods still on the floor.
class MonitorActiveLot {
  const MonitorActiveLot({
    required this.lotId,
    required this.productName,
    required this.businessDate,
    required this.ageDays,
    required this.remainingHandling,
    required this.receivedHandling,
    required this.handlingUom,
    required this.ownershipModel,
    this.lotTag,
    this.lotCode,
    this.supplierName,
    this.remainingBase,
    this.receivedBase,
    this.baseUom,
  });

  final String lotId;
  final String productName;
  final String businessDate;
  final int ageDays;
  final double remainingHandling;
  final double receivedHandling;
  final String handlingUom;
  final String ownershipModel;
  final String? lotTag;
  final String? lotCode;
  final String? supplierName;
  final double? remainingBase;
  final double? receivedBase;
  final String? baseUom;

  bool get isOwned => ownershipModel != 'consignment';
  bool get isEmpty => remainingHandling <= 0.0005;

  String get ageText => switch (ageDays) {
    <= 0 => 'today',
    1 => 'yesterday',
    _ => '$ageDays days old',
  };

  String get remainingText {
    final parts = <String>['${Money.formatQty(remainingHandling)} $handlingUom'];
    if (remainingBase != null) {
      parts.add('${Money.formatQty(remainingBase!)} ${baseUom ?? 'measured'}');
    }
    return parts.join(' · ');
  }

  String get receivedText {
    final parts = <String>['${Money.formatQty(receivedHandling)} $handlingUom'];
    if (receivedBase != null) {
      parts.add('${Money.formatQty(receivedBase!)} ${baseUom ?? 'measured'}');
    }
    return parts.join(' · ');
  }

  factory MonitorActiveLot.fromMap(Map<String, dynamic> map) => MonitorActiveLot(
    lotId: _text(map['lotId']),
    productName: _text(map['productName'], 'Item'),
    businessDate: _text(map['businessDate']),
    ageDays: _count(map['ageDays']),
    remainingHandling: _money(map['remainingHandling']),
    receivedHandling: _money(map['receivedHandling']),
    handlingUom: _text(map['handlingUom'], 'qty'),
    ownershipModel: _text(map['ownershipModel'], 'owned'),
    lotTag: _maybe(map['lotTag']),
    lotCode: _maybe(map['lotCode']),
    supplierName: _maybe(map['supplierName']),
    remainingBase: _optional(map['remainingBase']),
    receivedBase: _optional(map['receivedBase']),
    baseUom: _maybe(map['baseUom']),
  );
}

/// A supplier statement, draft or finalized.
class MonitorStatement {
  const MonitorStatement({
    required this.statementId,
    required this.nodeId,
    required this.statementNumber,
    required this.status,
    required this.statementType,
    required this.businessDate,
    required this.merchandiseSubtotal,
    required this.commissionRate,
    required this.commissionAmount,
    required this.adjustmentTotal,
    required this.netPayable,
    this.supplierName,
    this.supplierCode,
    this.fromDate,
    this.toDate,
  });

  final String statementId;
  final String nodeId;
  final String statementNumber;
  final String status;
  final String statementType;
  final String businessDate;
  final double merchandiseSubtotal;
  final double commissionRate;
  final double commissionAmount;
  final double adjustmentTotal;
  final double netPayable;
  final String? supplierName;
  final String? supplierCode;
  final String? fromDate;
  final String? toDate;

  bool get isPurchase => statementType == 'owned_purchase';
  bool get isVoid => status == 'void';
  String get typeLabel => isPurchase ? 'Purchase' : 'Consignment';
  String get supplierLabel => supplierName ?? supplierCode ?? 'Supplier';
  String get periodText => fromDate == null || toDate == null
      ? businessDate
      : fromDate == toDate
      ? '$fromDate'
      : '$fromDate to $toDate';

  factory MonitorStatement.fromMap(Map<String, dynamic> map) => MonitorStatement(
    statementId: _text(map['statementId']),
    nodeId: _text(map['nodeId']),
    statementNumber: _text(map['statementNumber'], 'Statement'),
    status: _text(map['status'], 'draft'),
    statementType: _text(map['statementType'], 'consignment'),
    businessDate: _text(map['businessDate']),
    merchandiseSubtotal: _money(map['merchandiseSubtotal']),
    commissionRate: _money(map['commissionRate']),
    commissionAmount: _money(map['commissionAmount']),
    adjustmentTotal: _money(map['adjustmentTotal']),
    netPayable: _money(map['netPayable']),
    supplierName: _maybe(map['supplierName']),
    supplierCode: _maybe(map['supplierCode']),
    fromDate: _maybe(map['fromDate']),
    toDate: _maybe(map['toDate']),
  );
}

class MonitorStatementLine {
  const MonitorStatementLine({
    required this.kind,
    required this.description,
    required this.unitPrice,
    required this.quantity,
    required this.amount,
    this.kilos,
    this.itemCode,
    this.note,
    this.sourceDate,
    this.receiptNo,
  });

  final String kind;
  final String description;
  final double unitPrice;
  final double quantity;
  final double amount;
  final double? kilos;
  final String? itemCode;
  final String? note;
  final String? sourceDate;
  final int? receiptNo;

  String get kindLabel => switch (kind) {
    'sale' => 'Sale',
    'manual' => 'Entered by hand',
    'purchase' => 'Purchase',
    _ => kind,
  };

  factory MonitorStatementLine.fromMap(Map<String, dynamic> map) => MonitorStatementLine(
    kind: _text(map['kind'], 'sale'),
    description: _text(map['description'], 'Item'),
    unitPrice: _money(map['unitPrice']),
    quantity: _money(map['quantity']),
    amount: _money(map['amount']),
    kilos: _optional(map['kilos']),
    itemCode: _maybe(map['itemCode']),
    note: _maybe(map['note']),
    sourceDate: _maybe(map['sourceDate']),
    receiptNo: map['receiptNo'] == null ? null : _count(map['receiptNo']),
  );
}

class MonitorStatementAdjustment {
  const MonitorStatementAdjustment({
    required this.type,
    required this.label,
    required this.amount,
    this.note,
  });

  final String type;
  final String label;
  final double amount;
  final String? note;

  bool get isCredit => type == 'credit';

  factory MonitorStatementAdjustment.fromMap(Map<String, dynamic> map) =>
      MonitorStatementAdjustment(
        type: _text(map['type'], 'deduction'),
        label: _text(map['label'], 'Adjustment'),
        amount: _money(map['amount']),
        note: _maybe(map['note']),
      );
}

class MonitorStatementDetail {
  const MonitorStatementDetail({
    required this.statement,
    required this.lines,
    required this.adjustments,
    required this.bagChargeTotal,
    required this.wageChargeTotal,
    this.notes,
    this.voidReason,
  });

  final MonitorStatement statement;
  final List<MonitorStatementLine> lines;
  final List<MonitorStatementAdjustment> adjustments;
  final double bagChargeTotal;
  final double wageChargeTotal;
  final String? notes;
  final String? voidReason;

  factory MonitorStatementDetail.fromMap(Map<String, dynamic> map) {
    final head = (map['statement'] as Map?)?.cast<String, dynamic>() ?? {};
    return MonitorStatementDetail(
      statement: MonitorStatement.fromMap({...head, 'nodeId': map['nodeId']}),
      lines: _rows(map['lines']).map(MonitorStatementLine.fromMap).toList(),
      adjustments: _rows(map['adjustments'])
          .map(MonitorStatementAdjustment.fromMap)
          .toList(),
      bagChargeTotal: _money(head['bagChargeTotal']),
      wageChargeTotal: _money(head['wageChargeTotal']),
      notes: _maybe(head['notes']),
      voidReason: _maybe(head['voidReason']),
    );
  }
}

/// What one supplier is owed, and what has been paid to them.
class MonitorSupplierAccount {
  const MonitorSupplierAccount({
    required this.supplierId,
    required this.supplierName,
    required this.balance,
    required this.paid,
    required this.statements,
    this.supplierCode,
    this.lastActivity,
    this.lastPayment,
  });

  final String supplierId;
  final String supplierName;
  final double balance;
  final double paid;
  final int statements;
  final String? supplierCode;
  final String? lastActivity;
  final String? lastPayment;

  bool get isSettled => balance.abs() < 0.005;
  bool get theyOweUs => balance < -0.005;

  factory MonitorSupplierAccount.fromMap(Map<String, dynamic> map) =>
      MonitorSupplierAccount(
        supplierId: _text(map['supplierId']),
        supplierName: _text(map['supplierName'], 'Supplier'),
        balance: _money(map['balance']),
        paid: _money(map['paid']),
        statements: _count(map['statements']),
        supplierCode: _maybe(map['supplierCode']),
        lastActivity: _maybe(map['lastActivity']),
        lastPayment: _maybe(map['lastPayment']),
      );
}

class MonitorAccountLine {
  const MonitorAccountLine({
    required this.kind,
    required this.date,
    required this.reference,
    required this.description,
    required this.owed,
    required this.paid,
    required this.balance,
    required this.reversed,
    this.detail,
  });

  final String kind;
  final String date;
  final String reference;
  final String description;
  final double owed;
  final double paid;
  final double balance;
  final bool reversed;
  final String? detail;

  factory MonitorAccountLine.fromMap(Map<String, dynamic> map) => MonitorAccountLine(
    kind: _text(map['kind'], 'statement'),
    date: _text(map['date']),
    reference: _text(map['reference']),
    description: _text(map['description']),
    owed: _money(map['owed']),
    paid: _money(map['paid']),
    balance: _money(map['balance']),
    reversed: map['reversed'] == true,
    detail: _maybe(map['detail']),
  );
}

class MonitorAccountSheet {
  const MonitorAccountSheet({
    required this.supplierName,
    required this.totalOwed,
    required this.totalPaid,
    required this.balance,
    required this.lines,
    this.supplierCode,
  });

  final String supplierName;
  final double totalOwed;
  final double totalPaid;
  final double balance;
  final List<MonitorAccountLine> lines;
  final String? supplierCode;

  factory MonitorAccountSheet.fromMap(Map<String, dynamic> map) {
    final supplier = (map['supplier'] as Map?)?.cast<String, dynamic>() ?? {};
    return MonitorAccountSheet(
      supplierName: _text(supplier['name'], 'Supplier'),
      supplierCode: _maybe(supplier['code']),
      totalOwed: _money(map['totalOwed']),
      totalPaid: _money(map['totalPaid']),
      balance: _money(map['balance']),
      lines: _rows(map['lines']).map(MonitorAccountLine.fromMap).toList(),
    );
  }
}
