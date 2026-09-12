/// Typed views of the Business Monitor API.
///
/// Every value here originates in a POS installation and reaches the phone
/// through the host's reporting archive. Nothing in the monitor writes, so
/// these models are read-only by design.
library;

double _money(Object? value) => (value as num?)?.toDouble() ?? 0;
double? _optional(Object? value) => (value as num?)?.toDouble();
int _count(Object? value) => (value as num?)?.toInt() ?? 0;
String _string(Object? value, [String fallback = '']) =>
    value is String && value.isNotEmpty ? value : fallback;

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> _rows(Object? value) => value is List
    ? value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
    : const [];

/// One POS installation reporting into this host.
class MonitorNode {
  const MonitorNode({required this.id, required this.name, this.lastSeenAt});

  final String id;
  final String name;
  final DateTime? lastSeenAt;

  factory MonitorNode.fromMap(Map<String, dynamic> map) => MonitorNode(
    id: _string(map['id']),
    name: _string(map['name'], 'POS'),
    lastSeenAt: DateTime.tryParse(_string(map['lastSeenAt']))?.toLocal(),
  );
}

/// A till, identified by the location and machine codes the POS stamps on
/// every document it creates.
class MonitorTerminal {
  const MonitorTerminal({
    required this.nodeId,
    required this.locCode,
    required this.macCode,
    this.name,
  });

  final String nodeId;
  final String locCode;
  final String macCode;
  final String? name;

  String get label => name?.isNotEmpty == true ? name! : '$locCode / $macCode';

  factory MonitorTerminal.fromMap(Map<String, dynamic> map) => MonitorTerminal(
    nodeId: _string(map['nodeId']),
    locCode: _string(map['locCode']),
    macCode: _string(map['macCode']),
    name: map['name'] as String?,
  );
}

/// A trading day a location has not closed yet.
class MonitorOpenDay {
  const MonitorOpenDay({
    required this.locCode,
    required this.status,
    required this.businessDate,
  });

  final String locCode;
  final String status;
  final String businessDate;

  factory MonitorOpenDay.fromMap(Map<String, dynamic> map) => MonitorOpenDay(
    locCode: _string(map['locCode']),
    status: _string(map['status']),
    businessDate: _string(map['businessDate']),
  );
}

/// One counter inside a shop.
class MonitorCounter {
  const MonitorCounter({required this.macCode, required this.name, required this.nodeId});

  final String macCode;
  final String name;
  final String nodeId;

  factory MonitorCounter.fromMap(Map<String, dynamic> map) => MonitorCounter(
    macCode: _string(map['macCode']),
    name: _string(map['name'], _string(map['macCode'])),
    nodeId: _string(map['nodeId']),
  );
}

/// One shop.
///
/// The location code is what separates one business from another: its own
/// catalog, its own customers, its own books. Everything the owner reads can be
/// asked for the whole business, one shop, or one counter inside a shop.
class MonitorLocation {
  const MonitorLocation({
    required this.locCode,
    required this.name,
    required this.businessCode,
    required this.counters,
  });

  final String locCode;
  final String name;
  final String? businessCode;
  final List<MonitorCounter> counters;

  String get subtitle => counters.isEmpty
      ? 'No counter has reported yet'
      : '${counters.length} counter${counters.length == 1 ? '' : 's'} · '
            '${counters.map((counter) => counter.name).join(' · ')}';

  factory MonitorLocation.fromMap(Map<String, dynamic> map) => MonitorLocation(
    locCode: _string(map['locCode']),
    name: _string(map['name'], _string(map['locCode'])),
    businessCode: map['businessCode'] as String?,
    counters: _rows(map['terminals']).map(MonitorCounter.fromMap).toList(),
  );
}

class MonitorFleet {
  const MonitorFleet({
    required this.nodes,
    required this.locations,
    required this.terminals,
    required this.openDays,
  });

  final List<MonitorNode> nodes;
  final List<MonitorLocation> locations;
  final List<MonitorTerminal> terminals;
  final List<MonitorOpenDay> openDays;

  static const empty = MonitorFleet(nodes: [], locations: [], terminals: [], openDays: []);

  MonitorLocation? locationOf(String? locCode) {
    if (locCode == null) return null;
    for (final location in locations) {
      if (location.locCode == locCode) return location;
    }
    return null;
  }

  factory MonitorFleet.fromMap(Map<String, dynamic> map) => MonitorFleet(
    nodes: _rows(map['nodes']).map(MonitorNode.fromMap).toList(),
    locations: _rows(map['locations']).map(MonitorLocation.fromMap).toList(),
    terminals: _rows(map['terminals']).map(MonitorTerminal.fromMap).toList(),
    openDays: _rows(map['openDays']).map(MonitorOpenDay.fromMap).toList(),
  );
}

/// A named money total, used for tender splits and cheque status groups.
class MonitorTotal {
  const MonitorTotal({
    required this.label,
    required this.count,
    required this.total,
  });

  final String label;
  final int count;
  final double total;

  factory MonitorTotal.fromMap(Map<String, dynamic> map, String labelKey) =>
      MonitorTotal(
        label: _string(map[labelKey], 'unknown'),
        count: _count(map['count']),
        total: _money(map['total']),
      );
}

/// Headline business position for the selected range.
class MonitorOverview {
  const MonitorOverview({
    required this.invoiceCount,
    required this.gross,
    required this.collected,
    required this.credit,
    required this.discount,
    required this.bagCharge,
    required this.wageCharge,
    required this.net,
    required this.refundCount,
    required this.refundTotal,
    required this.cashReturned,
    required this.tenders,
    required this.outstandingTotal,
    required this.outstandingInvoices,
    required this.cheques,
    required this.openShifts,
    required this.expectedCash,
    required this.advanceHeld,
  });

  final int invoiceCount;
  final double gross;
  final double collected;
  final double credit;
  final double discount;
  final double bagCharge;
  final double wageCharge;
  final double net;
  final int refundCount;
  /// Value of the goods returned, already taken off [net].
  final double refundTotal;
  /// Money actually handed back, already taken off [collected].
  final double cashReturned;
  final List<MonitorTotal> tenders;
  final double outstandingTotal;
  final int outstandingInvoices;
  final List<MonitorTotal> cheques;
  final int openShifts;
  final double expectedCash;
  final double advanceHeld;

  double get cashCollected => tenders
      .where((tender) => tender.label == 'cash')
      .fold(0, (sum, tender) => sum + tender.total);

  /// Cheques still carrying risk: received or banked but not yet cleared.
  double get chequesInFlight => cheques
      .where((row) => row.label == 'received' || row.label == 'deposited')
      .fold(0, (sum, row) => sum + row.total);

  static const empty = MonitorOverview(
    invoiceCount: 0, gross: 0, collected: 0, credit: 0, discount: 0,
    bagCharge: 0, wageCharge: 0, net: 0, refundCount: 0, refundTotal: 0, cashReturned: 0,
    tenders: [], outstandingTotal: 0, outstandingInvoices: 0, cheques: [],
    openShifts: 0, expectedCash: 0, advanceHeld: 0,
  );

  factory MonitorOverview.fromMap(Map<String, dynamic> map) {
    final sales = _map(map['sales']);
    final refunds = _map(map['refunds']);
    final outstanding = _map(map['outstanding']);
    final drawers = _map(map['drawers']);
    final advance = _map(map['customerAdvance']);
    return MonitorOverview(
      invoiceCount: _count(sales['invoiceCount']),
      gross: _money(sales['gross']),
      collected: _money(sales['collected']),
      credit: _money(sales['credit']),
      discount: _money(sales['discount']),
      bagCharge: _money(sales['bagCharge']),
      wageCharge: _money(sales['wageCharge']),
      net: _money(sales['net']),
      refundCount: _count(refunds['count']),
      refundTotal: _money(refunds['total']),
      cashReturned: _money(refunds['cashReturned']),
      tenders: _rows(map['tenders'])
          .map((row) => MonitorTotal.fromMap(row, 'method'))
          .toList(),
      outstandingTotal: _money(outstanding['total']),
      outstandingInvoices: _count(outstanding['invoiceCount']),
      cheques: _rows(map['cheques'])
          .map((row) => MonitorTotal.fromMap(row, 'status'))
          .toList(),
      openShifts: _count(drawers['openShifts']),
      expectedCash: _money(drawers['expectedCash']),
      advanceHeld: _money(advance['held']),
    );
  }
}

/// One bar in the sales breakdown.
class MonitorSalesBucket {
  const MonitorSalesBucket({
    required this.bucket,
    required this.invoiceCount,
    required this.gross,
    required this.net,
    required this.collected,
    required this.credit,
    required this.returned,
    required this.refundCount,
  });

  final String bucket;
  final int invoiceCount;
  final double gross;

  /// Sales after returns. This is the figure every screen shows.
  final double net;
  final double collected;
  final double credit;
  final double returned;
  final int refundCount;

  bool get hasReturns => returned > 0.005;

  factory MonitorSalesBucket.fromMap(Map<String, dynamic> map) =>
      MonitorSalesBucket(
        bucket: _string(map['bucket'], '—'),
        invoiceCount: _count(map['invoiceCount']),
        gross: _money(map['gross']),
        net: map['net'] == null ? _money(map['gross']) : _money(map['net']),
        collected: _money(map['collected']),
        credit: _money(map['credit']),
        returned: _money(map['returned']),
        refundCount: _count(map['refundCount']),
      );
}

/// An item's contribution to sales, in both units of measure.
class MonitorSalesItem {
  const MonitorSalesItem({
    required this.itemCode,
    required this.description,
    required this.lineCount,
    required this.handlingQty,
    required this.handlingUom,
    required this.baseQty,
    required this.baseUom,
    required this.total,
  });

  final String itemCode;
  final String description;
  final int lineCount;
  final double handlingQty;
  final String handlingUom;
  final double baseQty;
  final String? baseUom;
  final double total;

  factory MonitorSalesItem.fromMap(Map<String, dynamic> map) =>
      MonitorSalesItem(
        itemCode: _string(map['itemCode']),
        description: _string(map['description'], 'Unnamed item'),
        lineCount: _count(map['lineCount']),
        handlingQty: _money(map['handlingQty']),
        handlingUom: _string(map['handlingUom'], 'qty'),
        baseQty: _money(map['baseQty']),
        baseUom: map['baseUom'] as String?,
        total: _money(map['total']),
      );
}

class MonitorSales {
  const MonitorSales({
    required this.groupBy,
    required this.label,
    required this.buckets,
    required this.items,
  });

  final String groupBy;
  final String label;
  final List<MonitorSalesBucket> buckets;
  final List<MonitorSalesItem> items;

  static const empty =
      MonitorSales(groupBy: 'day', label: 'Business day', buckets: [], items: []);

  factory MonitorSales.fromMap(Map<String, dynamic> map) => MonitorSales(
    groupBy: _string(map['groupBy'], 'day'),
    label: _string(map['label'], 'Business day'),
    buckets: _rows(map['rows']).map(MonitorSalesBucket.fromMap).toList(),
    items: _rows(map['items']).map(MonitorSalesItem.fromMap).toList(),
  );
}

/// One finalized bill in the archive.
class MonitorInvoice {
  const MonitorInvoice({
    required this.nodeId,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.receiptNo,
    required this.locCode,
    required this.macCode,
    required this.businessDate,
    required this.customerCode,
    required this.status,
    required this.grandTotal,
    required this.paidTotal,
    required this.balance,
    required this.returnedTotal,
    required this.returnedCashTotal,
    required this.refundStatus,
  });

  final String nodeId;
  final String invoiceId;
  final String invoiceNumber;
  final String receiptNo;
  final String locCode;
  final String macCode;
  final String businessDate;
  final String customerCode;
  final String status;
  final double grandTotal;
  final double paidTotal;
  final double balance;

  /// Value of goods returned against this bill, and money handed back.
  final double returnedTotal;
  final double returnedCashTotal;

  /// 'none', 'partial', or 'full' — a bill returned in full is a reversed bill.
  final String refundStatus;

  bool get hasBalance => balance > 0.005;
  bool get isReturned => refundStatus != 'none';
  bool get isFullyReturned => refundStatus == 'full';
  String get returnLabel => switch (refundStatus) {
    'full' => 'Returned',
    'partial' => 'Part returned',
    _ => '',
  };

  /// What the sale is worth after returns, and what the shop kept of it.
  double get netTotal => grandTotal - returnedTotal;
  double get netCollected => paidTotal - returnedCashTotal;
  String get terminal => '$locCode/$macCode';

  factory MonitorInvoice.fromMap(Map<String, dynamic> map) => MonitorInvoice(
    nodeId: _string(map['nodeId']),
    invoiceId: _string(map['invoiceId']),
    invoiceNumber: _string(map['invoiceNumber'], 'Bill'),
    receiptNo: _string(map['receiptNo']),
    locCode: _string(map['locCode']),
    macCode: _string(map['macCode']),
    businessDate: _string(map['businessDate']),
    customerCode: _string(map['customerCode'], 'Walk-in'),
    status: _string(map['status'], 'unknown'),
    grandTotal: _money(map['grandTotal']),
    paidTotal: _money(map['paidTotal']),
    balance: _money(map['balance']),
    returnedTotal: _money(map['returnedTotal']),
    returnedCashTotal: _money(map['returnedCashTotal']),
    refundStatus: _string(map['refundStatus'], 'none'),
  );
}

class MonitorInvoicePage {
  const MonitorInvoicePage({
    required this.total,
    required this.rows,
    required this.offset,
    required this.limit,
    required this.netTotal,
    required this.netCollected,
    required this.returnedTotal,
  });

  final int total;
  final List<MonitorInvoice> rows;
  final int offset;
  final int limit;

  /// Totals for everything the filter matched, not just the loaded page,
  /// and already net of returns.
  final double netTotal;
  final double netCollected;
  final double returnedTotal;

  bool get hasMore => offset + rows.length < total;
  bool get hasReturns => returnedTotal > 0.005;

  static const empty = MonitorInvoicePage(
    total: 0, rows: [], offset: 0, limit: 40,
    netTotal: 0, netCollected: 0, returnedTotal: 0,
  );

  factory MonitorInvoicePage.fromMap(Map<String, dynamic> map) =>
      MonitorInvoicePage(
        total: _count(map['total']),
        rows: _rows(map['rows']).map(MonitorInvoice.fromMap).toList(),
        offset: _count(map['offset']),
        limit: _count(map['limit']),
        netTotal: _money(map['netTotal']),
        netCollected: _money(map['netCollected']),
        returnedTotal: _money(map['returnedTotal']),
      );
}

/// A sold line, carrying whichever units the POS recorded it in.
class MonitorInvoiceLine {
  const MonitorInvoiceLine({
    required this.description,
    required this.itemCode,
    required this.handlingQty,
    required this.handlingUom,
    required this.baseQty,
    required this.baseUom,
    required this.unitPrice,
    required this.pricingBasis,
    required this.merchandiseTotal,
    required this.bagChargeTotal,
    required this.wageChargeTotal,
    required this.total,
  });

  final String description;
  final String itemCode;
  final double handlingQty;
  final String handlingUom;
  final double? baseQty;
  final String? baseUom;
  final double unitPrice;
  final String pricingBasis;
  final double merchandiseTotal;
  final double bagChargeTotal;
  final double wageChargeTotal;
  final double total;

  factory MonitorInvoiceLine.fromMap(Map<String, dynamic> map) =>
      MonitorInvoiceLine(
        description: _string(map['description'], 'Item'),
        itemCode: _string(map['itemCode']),
        handlingQty: _money(map['handlingQty']),
        handlingUom: _string(map['handlingUom'], 'qty'),
        baseQty: _optional(map['baseQty']),
        baseUom: map['baseUom'] as String?,
        unitPrice: _money(map['unitPrice']),
        pricingBasis: _string(map['pricingBasis'], 'qty'),
        merchandiseTotal: _money(map['merchandiseTotal']),
        bagChargeTotal: _money(map['bagChargeTotal']),
        wageChargeTotal: _money(map['wageChargeTotal']),
        total: _money(map['total']),
      );
}

class MonitorInvoicePayment {
  const MonitorInvoicePayment({
    required this.method,
    required this.amount,
    this.chequeNumber,
    this.chequeBank,
  });

  final String method;
  final double amount;
  final String? chequeNumber;
  final String? chequeBank;

  factory MonitorInvoicePayment.fromMap(Map<String, dynamic> map) =>
      MonitorInvoicePayment(
        method: _string(map['method'], 'unknown'),
        amount: _money(map['amount']),
        chequeNumber: map['chequeNumber'] as String?,
        chequeBank: map['chequeBank'] as String?,
      );
}

class MonitorInvoiceDetail {
  const MonitorInvoiceDetail({
    required this.invoice,
    required this.lines,
    required this.payments,
    required this.subtotal,
    required this.discountTotal,
    required this.bagChargeTotal,
    required this.wageChargeTotal,
    required this.changeAmt,
  });

  final MonitorInvoice invoice;
  final List<MonitorInvoiceLine> lines;
  final List<MonitorInvoicePayment> payments;
  final double subtotal;
  final double discountTotal;
  final double bagChargeTotal;
  final double wageChargeTotal;
  final double changeAmt;

  factory MonitorInvoiceDetail.fromMap(Map<String, dynamic> map) {
    final invoice = _map(map['invoice']);
    return MonitorInvoiceDetail(
      invoice: MonitorInvoice.fromMap({...invoice, 'nodeId': map['nodeId']}),
      lines: _rows(map['lines']).map(MonitorInvoiceLine.fromMap).toList(),
      payments:
          _rows(map['payments']).map(MonitorInvoicePayment.fromMap).toList(),
      subtotal: _money(invoice['subtotal']),
      discountTotal: _money(invoice['discountTotal']),
      bagChargeTotal: _money(invoice['bagChargeTotal']),
      wageChargeTotal: _money(invoice['wageChargeTotal']),
      changeAmt: _money(invoice['changeAmt']),
    );
  }
}

/// A cashier's drawer session and how it reconciled.
class MonitorShift {
  const MonitorShift({
    required this.shiftId,
    required this.locCode,
    required this.macCode,
    required this.businessDate,
    required this.shiftNo,
    required this.status,
    required this.openingTotal,
    required this.expectedTotal,
    required this.declaredTotal,
    required this.varianceTotal,
    required this.varianceReason,
  });

  final String shiftId;
  final String locCode;
  final String macCode;
  final String businessDate;
  final int shiftNo;
  final String status;
  final double openingTotal;
  final double expectedTotal;
  final double? declaredTotal;
  final double? varianceTotal;
  final String? varianceReason;

  bool get isOpen => status == 'open' || status == 'blind_closed';
  bool get hasVariance => (varianceTotal ?? 0).abs() > 0.005;
  String get terminal => '$locCode/$macCode';

  factory MonitorShift.fromMap(Map<String, dynamic> map) => MonitorShift(
    shiftId: _string(map['shiftId']),
    locCode: _string(map['locCode']),
    macCode: _string(map['macCode']),
    businessDate: _string(map['businessDate']),
    shiftNo: _count(map['shiftNo']),
    status: _string(map['status'], 'unknown'),
    openingTotal: _money(map['openingTotal']),
    expectedTotal: _money(map['expectedTotal']),
    declaredTotal: _optional(map['declaredTotal']),
    varianceTotal: _optional(map['varianceTotal']),
    varianceReason: map['varianceReason'] as String?,
  );
}

class MonitorCash {
  const MonitorCash({required this.shifts, required this.movements});

  final List<MonitorShift> shifts;
  final List<MonitorTotal> movements;

  static const empty = MonitorCash(shifts: [], movements: []);

  factory MonitorCash.fromMap(Map<String, dynamic> map) => MonitorCash(
    shifts: _rows(map['shifts']).map(MonitorShift.fromMap).toList(),
    movements: _rows(map['movements'])
        .map((row) => MonitorTotal.fromMap(row, 'type'))
        .toList(),
  );
}

/// What one customer still owes across all their unpaid bills.
class MonitorReceivable {
  const MonitorReceivable({
    required this.customerCode,
    required this.customerName,
    required this.invoiceCount,
    required this.balance,
    required this.oldest,
    this.customerMobile,
  });

  final String customerCode;
  final String? customerName;
  final String? customerMobile;
  final int invoiceCount;
  final double balance;
  final String oldest;

  String get title => customerName?.isNotEmpty == true
      ? customerName!
      : customerCode;

  factory MonitorReceivable.fromMap(Map<String, dynamic> map) =>
      MonitorReceivable(
        customerCode: _string(map['customerCode'], 'Walk-in'),
        customerName: map['customerName'] as String?,
        customerMobile: _nullableString(map['customerMobile']),
        invoiceCount: _count(map['invoiceCount']),
        balance: _money(map['balance']),
        oldest: _string(map['oldest']),
      );
}

String? _nullableString(Object? value) {
  final text = value == null ? '' : '$value'.trim();
  return text.isEmpty ? null : text;
}

class MonitorCheque {
  const MonitorCheque({
    required this.chequeNumber,
    required this.partyName,
    required this.bankName,
    required this.chequeDate,
    required this.amount,
    required this.status,
  });

  final String chequeNumber;
  final String partyName;
  final String? bankName;
  final String chequeDate;
  final double amount;
  final String status;

  factory MonitorCheque.incoming(Map<String, dynamic> map) => MonitorCheque(
    chequeNumber: _string(map['chequeNumber'], 'No number'),
    partyName: _string(map['drawerName'], 'Unknown drawer'),
    bankName: map['bankName'] as String?,
    chequeDate: _string(map['chequeDate']),
    amount: _money(map['amount']),
    status: _string(map['status'], 'unknown'),
  );

  factory MonitorCheque.issued(Map<String, dynamic> map) => MonitorCheque(
    chequeNumber: _string(map['chequeNumber'], 'No number'),
    partyName: _string(map['payeeName'], 'Unknown payee'),
    bankName: map['reference'] as String?,
    chequeDate: _string(map['chequeDate']),
    amount: _money(map['amount']),
    status: _string(map['status'], 'unknown'),
  );
}

class MonitorCheques {
  const MonitorCheques({required this.incoming, required this.issued});

  final List<MonitorCheque> incoming;
  final List<MonitorCheque> issued;

  static const empty = MonitorCheques(incoming: [], issued: []);

  factory MonitorCheques.fromMap(Map<String, dynamic> map) => MonitorCheques(
    incoming: _rows(map['incoming']).map(MonitorCheque.incoming).toList(),
    issued: _rows(map['issued']).map(MonitorCheque.issued).toList(),
  );
}

/// An item's on-hand position. A dual-unit item carries both measures, for
/// example 40 bags and 2,000 kg of the same onions.
class MonitorStockItem {
  const MonitorStockItem({
    required this.productKey,
    required this.name,
    required this.nodeName,
    required this.category,
    required this.unitPrice,
    required this.handlingQty,
    required this.handlingUom,
    required this.baseQty,
    required this.baseUom,
  });

  final String productKey;
  final String name;
  final String nodeName;
  final String? category;
  final double unitPrice;
  final double handlingQty;
  final String handlingUom;
  final double? baseQty;
  final String? baseUom;

  bool get isDual => baseQty != null && baseUom != null;

  factory MonitorStockItem.fromMap(Map<String, dynamic> map) =>
      MonitorStockItem(
        productKey: _string(map['productKey']),
        name: _string(map['name'], 'Unnamed item'),
        nodeName: _string(map['nodeName'], 'POS'),
        category: map['category'] as String?,
        unitPrice: _money(map['unitPrice']),
        handlingQty: _money(map['handlingQty']),
        handlingUom: _string(map['handlingUom'], 'qty'),
        baseQty: _optional(map['baseQty']),
        baseUom: map['baseUom'] as String?,
      );
}

/// A received batch, still traceable to the GRN and supplier it arrived on.
class MonitorLot {
  const MonitorLot({
    required this.lotId,
    required this.lotCode,
    required this.grnNo,
    required this.productName,
    required this.supplierName,
    required this.businessDate,
    required this.ownershipModel,
    required this.receivedHandling,
    required this.remainingHandling,
    required this.receivedBase,
    required this.remainingBase,
    required this.handlingUom,
    required this.baseUom,
  });

  final String lotId;
  final String? lotCode;
  final String? grnNo;
  final String productName;
  final String? supplierName;
  final String businessDate;
  final String ownershipModel;
  final double receivedHandling;
  final double remainingHandling;
  final double? receivedBase;
  final double? remainingBase;
  final String handlingUom;
  final String? baseUom;

  bool get isConsignment => ownershipModel == 'consignment';
  bool get isDual => remainingBase != null && baseUom != null;
  double get soldHandling => receivedHandling - remainingHandling;

  factory MonitorLot.fromMap(Map<String, dynamic> map) => MonitorLot(
    lotId: _string(map['lotId']),
    lotCode: map['lotCode'] as String?,
    grnNo: map['grnNo'] as String?,
    productName: _string(map['productName'], 'Item'),
    supplierName: map['supplierName'] as String?,
    businessDate: _string(map['businessDate']),
    ownershipModel: _string(map['ownershipModel'], 'owned'),
    receivedHandling: _money(map['receivedHandling']),
    remainingHandling: _money(map['remainingHandling']),
    receivedBase: _optional(map['receivedBase']),
    remainingBase: _optional(map['remainingBase']),
    handlingUom: _string(map['handlingUom'], 'qty'),
    baseUom: map['baseUom'] as String?,
  );
}

/// A goods received note.
class MonitorGrn {
  const MonitorGrn({
    required this.grnId,
    required this.grnNumber,
    required this.supplierName,
    required this.businessDate,
    required this.status,
    required this.vehicleNo,
  });

  final String grnId;
  final String grnNumber;
  final String? supplierName;
  final String businessDate;
  final String status;
  final String? vehicleNo;

  factory MonitorGrn.fromMap(Map<String, dynamic> map) => MonitorGrn(
    grnId: _string(map['grnId']),
    grnNumber: _string(map['grnNumber'], 'GRN'),
    supplierName: map['supplierName'] as String?,
    businessDate: _string(map['businessDate']),
    status: _string(map['status'], 'unknown'),
    vehicleNo: map['vehicleNo'] as String?,
  );
}

List<T> parseRows<T>(
  Map<String, dynamic> body,
  T Function(Map<String, dynamic>) parse,
) => _rows(body['rows']).map(parse).toList();
