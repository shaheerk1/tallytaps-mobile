import 'dart:convert';

/// One sale line as it was billed, for checking a supply.
class SaleLine {
  const SaleLine({
    required this.id,
    required this.date,
    required this.receiptNo,
    required this.seqNo,
    required this.itemCode,
    required this.description,
    required this.supplierCode,
    required this.pricingBasis,
    required this.unitPrice,
    required this.handlingQty,
    required this.handlingUom,
    required this.baseQty,
    required this.baseUom,
    required this.merchandiseTotal,
    required this.bagChargeTotal,
    required this.wageChargeTotal,
    required this.returnedHandling,
    required this.returnedBase,
    required this.netHandling,
    required this.netBase,
    required this.netMerchandise,
    this.customerCode,
    this.locCode,
    this.macCode,
  });

  final String id;
  final String date;
  final int receiptNo, seqNo;
  final String itemCode, description;
  final String? supplierCode, customerCode, locCode, macCode;
  final String pricingBasis;
  final double unitPrice;
  final double handlingQty;
  final String handlingUom;
  final double? baseQty;
  final String? baseUom;
  final double merchandiseTotal, bagChargeTotal, wageChargeTotal;
  final double? returnedHandling, returnedBase;
  final double netHandling;
  final double? netBase;
  final double netMerchandise;

  bool get wasReturned => (returnedHandling ?? 0) > 0 || (returnedBase ?? 0) > 0;

  /// What a line is counted by: weighed goods by their measure, the rest by count.
  double get measure => pricingBasis == 'kilos' ? (netBase ?? 0) : netHandling;

  factory SaleLine.fromMap(Map<String, dynamic> map) => SaleLine(
    id: '${map['id']}',
    date: '${map['date'] ?? ''}',
    receiptNo: _int(map['receiptNo']),
    seqNo: _int(map['seqNo']),
    itemCode: '${map['itemCode'] ?? ''}',
    description: '${map['description'] ?? ''}',
    supplierCode: _text(map['supplierCode']),
    customerCode: _text(map['customerCode']),
    locCode: _text(map['locCode']),
    macCode: _text(map['macCode']),
    pricingBasis: map['pricingBasis'] == 'kilos' ? 'kilos' : 'qty',
    unitPrice: _double(map['unitPrice']) ?? 0,
    handlingQty: _double(map['handlingQty']) ?? 0,
    handlingUom: '${map['handlingUom'] ?? 'qty'}',
    baseQty: _double(map['baseQty']),
    baseUom: _text(map['baseUom']),
    merchandiseTotal: _double(map['merchandiseTotal']) ?? 0,
    bagChargeTotal: _double(map['bagChargeTotal']) ?? 0,
    wageChargeTotal: _double(map['wageChargeTotal']) ?? 0,
    returnedHandling: _double(map['returnedHandling']),
    returnedBase: _double(map['returnedBase']),
    netHandling: _double(map['netHandling']) ?? _double(map['handlingQty']) ?? 0,
    netBase: _double(map['netBase']) ?? _double(map['baseQty']),
    netMerchandise: _double(map['netMerchandise']) ?? _double(map['merchandiseTotal']) ?? 0,
  );

  Map<String, Object?> toMap() => {
    'id': id, 'date': date, 'receiptNo': receiptNo, 'seqNo': seqNo,
    'itemCode': itemCode, 'description': description, 'supplierCode': supplierCode,
    'customerCode': customerCode, 'locCode': locCode, 'macCode': macCode,
    'pricingBasis': pricingBasis, 'unitPrice': unitPrice,
    'handlingQty': handlingQty, 'handlingUom': handlingUom,
    'baseQty': baseQty, 'baseUom': baseUom,
    'merchandiseTotal': merchandiseTotal, 'bagChargeTotal': bagChargeTotal,
    'wageChargeTotal': wageChargeTotal,
    'returnedHandling': returnedHandling, 'returnedBase': returnedBase,
    'netHandling': netHandling, 'netBase': netBase, 'netMerchandise': netMerchandise,
  };
}

/// An item code the range holds, offered to pick from.
class SaleLineItemCode {
  const SaleLineItemCode({
    required this.itemCode,
    required this.description,
    required this.lineCount,
    required this.merchandise,
  });

  final String itemCode, description;
  final int lineCount;
  final double merchandise;

  factory SaleLineItemCode.fromMap(Map<String, dynamic> map) => SaleLineItemCode(
    itemCode: '${map['itemCode'] ?? ''}',
    description: '${map['description'] ?? ''}',
    lineCount: _int(map['lineCount']),
    merchandise: _double(map['merchandise']) ?? 0,
  );
}

/// A page of sale lines, with the item codes that can be picked from alongside.
class SaleLinePage {
  const SaleLinePage({
    required this.lines,
    required this.itemCodes,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<SaleLine> lines;
  final List<SaleLineItemCode> itemCodes;
  final int total, limit, offset;

  bool get hasMore => offset + lines.length < total;

  static const empty = SaleLinePage(lines: [], itemCodes: [], total: 0, limit: 0, offset: 0);

  factory SaleLinePage.fromMap(Map<String, dynamic> map) => SaleLinePage(
    lines: (map['lines'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => SaleLine.fromMap(Map<String, dynamic>.from(row)))
        .toList(),
    itemCodes: (map['itemCodes'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => SaleLineItemCode.fromMap(Map<String, dynamic>.from(row)))
        .toList(),
    total: _int(map['total']),
    limit: _int(map['limit']),
    offset: _int(map['offset']),
  );
}

// ── The summary ───────────────────────────────────────────────

/// One item sold at one rate: how much of it went, and for how much.
class SupplyCheckRow {
  const SupplyCheckRow({
    required this.itemCode,
    required this.description,
    required this.unitPrice,
    required this.pricingBasis,
    required this.lineCount,
    required this.handlingQty,
    required this.handlingUom,
    required this.baseQty,
    required this.baseUom,
    required this.merchandise,
  });

  final String itemCode, description;
  final double unitPrice;
  final String pricingBasis;
  final int lineCount;
  final double handlingQty;
  final String handlingUom;
  final double? baseQty;
  final String? baseUom;
  final double merchandise;
}

/// Everything under one heading: the whole check, or one day of it.
class SupplyCheckGroup {
  const SupplyCheckGroup({
    required this.label,
    required this.rows,
    required this.merchandise,
    required this.commission,
    required this.netPayable,
  });

  final String label;
  final List<SupplyCheckRow> rows;
  final double merchandise, commission, netPayable;
}

/// What the chosen lines come to.
///
/// Grouped by item and by the rate it went out at, because the same goods often
/// leave at two or three prices in a day and a supply is settled on each.
/// Grouping by date breaks the same summary down day by day, each day carrying
/// its own commission, so the days add up to the total rather than being
/// re-derived from it.
class SupplyCheckSummary {
  const SupplyCheckSummary({
    required this.groups,
    required this.merchandise,
    required this.commission,
    required this.netPayable,
    required this.lineCount,
    required this.packagingAndWage,
    required this.returnedLineCount,
  });

  final List<SupplyCheckGroup> groups;
  final double merchandise, commission, netPayable, packagingAndWage;
  final int lineCount, returnedLineCount;

  bool get isEmpty => lineCount == 0;

  static const empty = SupplyCheckSummary(
    groups: [], merchandise: 0, commission: 0, netPayable: 0,
    lineCount: 0, packagingAndWage: 0, returnedLineCount: 0,
  );

  static SupplyCheckSummary of(
    Iterable<SaleLine> lines, {
    double commissionPercent = 0,
    bool groupByDate = false,
  }) {
    final chosen = lines.toList();
    if (chosen.isEmpty) return empty;
    final rate = commissionPercent.isFinite ? commissionPercent.clamp(0, 100).toDouble() : 0.0;

    final buckets = <String, List<SaleLine>>{};
    for (final line in chosen) {
      final key = groupByDate ? line.date : '';
      buckets.putIfAbsent(key, () => []).add(line);
    }
    final keys = buckets.keys.toList()..sort();

    final groups = <SupplyCheckGroup>[];
    for (final key in keys) {
      final rows = _rowsOf(buckets[key]!);
      final merchandise = _money(rows.fold<double>(0, (sum, row) => sum + row.merchandise));
      final commission = _money(merchandise * rate / 100);
      groups.add(SupplyCheckGroup(
        label: key.isEmpty ? 'All of it' : key,
        rows: rows,
        merchandise: merchandise,
        commission: commission,
        netPayable: _money(merchandise - commission),
      ));
    }

    return SupplyCheckSummary(
      groups: groups,
      // Summed from the groups, so what is shown adds up to what is totalled.
      merchandise: _money(groups.fold<double>(0, (sum, group) => sum + group.merchandise)),
      commission: _money(groups.fold<double>(0, (sum, group) => sum + group.commission)),
      netPayable: _money(groups.fold<double>(0, (sum, group) => sum + group.netPayable)),
      lineCount: chosen.length,
      packagingAndWage: _money(
        chosen.fold<double>(0, (sum, line) => sum + line.bagChargeTotal + line.wageChargeTotal),
      ),
      returnedLineCount: chosen.where((line) => line.wasReturned).length,
    );
  }

  static List<SupplyCheckRow> _rowsOf(List<SaleLine> lines) {
    final byRate = <String, List<SaleLine>>{};
    for (final line in lines) {
      // The rate is part of the key, so the same goods at two prices stay apart.
      byRate.putIfAbsent('${line.itemCode}@${line.unitPrice}', () => []).add(line);
    }
    final rows = byRate.values.map((group) {
      final first = group.first;
      final base = group.any((line) => line.netBase != null)
          ? group.fold<double>(0, (sum, line) => sum + (line.netBase ?? 0))
          : null;
      return SupplyCheckRow(
        itemCode: first.itemCode,
        description: first.description,
        unitPrice: first.unitPrice,
        pricingBasis: first.pricingBasis,
        lineCount: group.length,
        handlingQty: _measure(group.fold<double>(0, (sum, line) => sum + line.netHandling)),
        handlingUom: first.handlingUom,
        baseQty: base == null ? null : _measure(base),
        baseUom: first.baseUom,
        merchandise: _money(group.fold<double>(0, (sum, line) => sum + line.netMerchandise)),
      );
    }).toList();
    rows.sort((a, b) {
      final byCode = a.itemCode.compareTo(b.itemCode);
      return byCode != 0 ? byCode : a.unitPrice.compareTo(b.unitPrice);
    });
    return rows;
  }
}

// ── A check kept on the phone ─────────────────────────────────

/// A summary someone saved, to look at again later.
///
/// It keeps the lines it was made from rather than only their totals, so it can
/// be reopened and re-read without the host being reachable, and so a saved
/// check never changes under the person who saved it.
class SavedSupplyCheck {
  const SavedSupplyCheck({
    required this.id,
    required this.title,
    required this.fromDate,
    required this.toDate,
    required this.supplierCodes,
    required this.itemCodes,
    required this.commissionPercent,
    required this.groupByDate,
    required this.lines,
    required this.createdAt,
    this.placeLabel,
    this.locCode,
    this.macCode,
  });

  final String id, title;
  final String fromDate, toDate;
  final List<String> supplierCodes, itemCodes;
  final double commissionPercent;
  final bool groupByDate;
  final List<SaleLine> lines;
  final DateTime createdAt;
  final String? placeLabel, locCode, macCode;

  SupplyCheckSummary get summary => SupplyCheckSummary.of(
    lines,
    commissionPercent: commissionPercent,
    groupByDate: groupByDate,
  );

  String get rangeLabel => fromDate == toDate ? fromDate : '$fromDate → $toDate';

  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'loc_code': locCode,
    'mac_code': macCode,
    'place_label': placeLabel,
    'from_date': fromDate,
    'to_date': toDate,
    'supplier_codes': supplierCodes.join(','),
    'item_codes': itemCodes.join(','),
    'commission_percent': commissionPercent,
    'group_by_date': groupByDate ? 1 : 0,
    'line_count': lines.length,
    'merchandise': summary.merchandise,
    'commission': summary.commission,
    'net_payable': summary.netPayable,
    'lines': jsonEncode(lines.map((line) => line.toMap()).toList()),
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory SavedSupplyCheck.fromRow(Map<String, Object?> row) => SavedSupplyCheck(
    id: row['id'] as String,
    title: row['title'] as String,
    locCode: row['loc_code'] as String?,
    macCode: row['mac_code'] as String?,
    placeLabel: row['place_label'] as String?,
    fromDate: '${row['from_date']}',
    toDate: '${row['to_date']}',
    supplierCodes: _codes(row['supplier_codes']),
    itemCodes: _codes(row['item_codes']),
    commissionPercent: _double(row['commission_percent']) ?? 0,
    groupByDate: _int(row['group_by_date']) == 1,
    lines: (jsonDecode('${row['lines']}') as List)
        .whereType<Map>()
        .map((line) => SaleLine.fromMap(Map<String, dynamic>.from(line)))
        .toList(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(_int(row['created_at'])),
  );

  static List<String> _codes(Object? value) => '${value ?? ''}'
      .split(',')
      .map((code) => code.trim())
      .where((code) => code.isNotEmpty)
      .toList();
}

double _money(double value) => (value * 100).round() / 100;
double _measure(double value) => (value * 1000).round() / 1000;

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty || text == 'null' ? null : text;
}
