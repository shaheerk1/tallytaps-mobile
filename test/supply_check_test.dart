import 'package:flutter_test/flutter_test.dart';

import 'package:tally/monitor/supply_check.dart';
import 'package:tally/monitor/supply_check_models.dart';

SaleLine line({
  String id = '1',
  String date = '2026-11-01',
  String itemCode = 'RCE',
  String description = 'Rice',
  String? supplierCode = 'PER',
  String pricingBasis = 'kilos',
  double unitPrice = 100,
  double handlingQty = 2,
  double? baseQty = 50,
  double merchandise = 5000,
  double bag = 0,
  double wage = 0,
  double returnedBase = 0,
  double returnedHandling = 0,
  double returnedMerchandise = 0,
}) => SaleLine(
  id: id,
  date: date,
  receiptNo: 1,
  seqNo: 1,
  itemCode: itemCode,
  description: description,
  supplierCode: supplierCode,
  pricingBasis: pricingBasis,
  unitPrice: unitPrice,
  handlingQty: handlingQty,
  handlingUom: 'bag',
  baseQty: baseQty,
  baseUom: 'kg',
  merchandiseTotal: merchandise,
  bagChargeTotal: bag,
  wageChargeTotal: wage,
  returnedHandling: returnedHandling > 0 ? returnedHandling : null,
  returnedBase: returnedBase > 0 ? returnedBase : null,
  netHandling: handlingQty - returnedHandling,
  netBase: baseQty == null ? null : baseQty - returnedBase,
  netMerchandise: merchandise - returnedMerchandise,
);

void main() {
  test('a supply code may hold spaces; only a comma starts the next one', () {
    // One code with spaces in it is one code.
    expect(supplyCodesOf('SBT IO BEST'), ['SBT IO BEST']);
    // Beside an ordinary one.
    expect(supplyCodesOf('b1,SBT IO BEST'), ['B1', 'SBT IO BEST']);
    // Space around a comma belongs to neither code.
    expect(supplyCodesOf(' b1 , SBT IO BEST '), ['B1', 'SBT IO BEST']);
    // A double space inside a code is the same code, not another one.
    expect(supplyCodesOf('SBT  IO   BEST'), ['SBT IO BEST']);
    expect(supplyCodesOf('sbt io best, SBT IO BEST'), ['SBT IO BEST']);
    // Nothing typed, nothing filtered.
    expect(supplyCodesOf(''), isEmpty);
    expect(supplyCodesOf(' , ,, '), isEmpty);
  });

  test('lines group by item and by the rate they went out at', () {
    final summary = SupplyCheckSummary.of([
      line(id: '1', unitPrice: 100, baseQty: 50, merchandise: 5000),
      line(id: '2', unitPrice: 100, baseQty: 30, merchandise: 3000),
      // The same goods, a different rate: its own row.
      line(id: '3', unitPrice: 110, baseQty: 20, merchandise: 2200),
      line(id: '4', itemCode: 'LEK', description: 'Leeks', unitPrice: 300, baseQty: 10, merchandise: 3000),
    ]);

    expect(summary.groups.length, 1);
    final rows = summary.groups.single.rows;
    expect(rows.length, 3);
    expect(rows.map((row) => '${row.itemCode}@${row.unitPrice}'), ['LEK@300.0', 'RCE@100.0', 'RCE@110.0']);

    final at100 = rows.firstWhere((row) => row.itemCode == 'RCE' && row.unitPrice == 100);
    expect(at100.lineCount, 2);
    expect(at100.baseQty, 80);
    expect(at100.handlingQty, 4);
    expect(at100.merchandise, 8000);
    expect(summary.merchandise, 13200);
  });

  test('commission comes off the goods to leave the net payable', () {
    final summary = SupplyCheckSummary.of(
      [line(merchandise: 10000), line(id: '2', merchandise: 5000)],
      commissionPercent: 10,
    );
    expect(summary.merchandise, 15000);
    expect(summary.commission, 1500);
    expect(summary.netPayable, 13500);
  });

  test('by date, each day carries its own commission and the days add up', () {
    final summary = SupplyCheckSummary.of(
      [
        line(id: '1', date: '2026-11-01', merchandise: 5000),
        line(id: '2', date: '2026-11-01', merchandise: 3333.33),
        line(id: '3', date: '2026-11-02', merchandise: 7000),
      ],
      commissionPercent: 7.5,
      groupByDate: true,
    );

    expect(summary.groups.map((group) => group.label), ['2026-11-01', '2026-11-02']);
    final first = summary.groups.first;
    expect(first.merchandise, 8333.33);
    expect(first.commission, 625.0);
    expect(first.netPayable, 7708.33);
    final second = summary.groups.last;
    expect(second.merchandise, 7000);
    expect(second.commission, 525);

    // What is shown adds up to what is totalled, to the cent.
    expect(summary.merchandise, first.merchandise + second.merchandise);
    expect(summary.commission, first.commission + second.commission);
    expect(summary.netPayable, first.netPayable + second.netPayable);
  });

  test('a returned line counts at what is left of it', () {
    final summary = SupplyCheckSummary.of([
      line(baseQty: 30, handlingQty: 3, merchandise: 3300, returnedBase: 15, returnedHandling: 1, returnedMerchandise: 1650),
    ]);
    final row = summary.groups.single.rows.single;
    expect(row.baseQty, 15);
    expect(row.handlingQty, 2);
    expect(row.merchandise, 1650);
    expect(summary.returnedLineCount, 1);
  });

  test('packaging and wage are counted apart from the goods', () {
    final summary = SupplyCheckSummary.of([
      line(merchandise: 5000, bag: 100, wage: 50),
      line(id: '2', merchandise: 3000, bag: 60, wage: 0),
    ]);
    expect(summary.merchandise, 8000);
    expect(summary.packagingAndWage, 210);
  });

  test('nothing picked is an empty summary, not a zero one', () {
    expect(SupplyCheckSummary.of(const []).isEmpty, isTrue);
    expect(SupplyCheckSummary.of([line()]).isEmpty, isFalse);
  });

  test('a saved check keeps its lines and reads back the same totals', () {
    final check = SavedSupplyCheck(
      id: 'c1',
      title: 'PER · 01 Nov',
      fromDate: '2026-11-01',
      toDate: '2026-11-02',
      supplierCodes: const ['PER', 'PRE'],
      itemCodes: const ['RCE'],
      commissionPercent: 10,
      groupByDate: true,
      lines: [line(id: '1', merchandise: 5000), line(id: '2', date: '2026-11-02', merchandise: 5000)],
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

    final read = SavedSupplyCheck.fromRow(check.toRow());
    expect(read.title, 'PER · 01 Nov');
    expect(read.supplierCodes, ['PER', 'PRE']);
    expect(read.groupByDate, isTrue);
    expect(read.lines.length, 2);
    expect(read.lines.first.itemCode, 'RCE');
    expect(read.summary.merchandise, 10000);
    expect(read.summary.commission, 1000);
    expect(read.summary.netPayable, 9000);
    expect(read.summary.groups.length, 2);
    expect(read.rangeLabel, '2026-11-01 → 2026-11-02');
  });

  test('a page of lines reads the server answer, returns and all', () {
    final page = SaleLinePage.fromMap({
      'total': 2,
      'limit': 400,
      'offset': 0,
      'itemCodes': [
        {'itemCode': 'RCE', 'description': 'Rice', 'lineCount': 2, 'merchandise': 8000},
      ],
      'lines': [
        {
          'id': '11', 'date': '2026-11-01', 'receiptNo': 7, 'seqNo': 1,
          'itemCode': 'RCE', 'description': 'Rice', 'supplierCode': 'PER',
          'pricingBasis': 'kilos', 'unitPrice': '100.00', 'handlingQty': 2, 'handlingUom': 'bag',
          'baseQty': 50, 'baseUom': 'kg', 'merchandiseTotal': 5000,
          'bagChargeTotal': 100, 'wageChargeTotal': 50, 'total': 5150,
          'returnedHandling': null, 'returnedBase': null,
          'netHandling': 2, 'netBase': 50, 'netMerchandise': 5000,
        },
        {
          'id': '12', 'date': '2026-11-02', 'receiptNo': 8, 'seqNo': 1,
          'itemCode': 'RCE', 'description': 'Rice', 'supplierCode': 'PRE',
          'pricingBasis': 'kilos', 'unitPrice': 100, 'handlingQty': 2, 'handlingUom': 'bag',
          'baseQty': 30, 'baseUom': 'kg', 'merchandiseTotal': 3000,
          'bagChargeTotal': 0, 'wageChargeTotal': 0, 'total': 3000,
          'returnedHandling': 1, 'returnedBase': 15, 'returnedMerchandise': 1500,
          'netHandling': 1, 'netBase': 15, 'netMerchandise': 1500,
        },
      ],
    });

    expect(page.total, 2);
    expect(page.hasMore, isFalse);
    expect(page.itemCodes.single.itemCode, 'RCE');
    // Money arrives as a string from a DECIMAL column and must still be a number.
    expect(page.lines.first.unitPrice, 100);
    expect(page.lines.last.wasReturned, isTrue);
    expect(page.lines.last.measure, 15);
    expect(SupplyCheckSummary.of(page.lines).merchandise, 6500);
  });
}
