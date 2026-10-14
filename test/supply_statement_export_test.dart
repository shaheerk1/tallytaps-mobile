import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/monitor/supply_check_models.dart';
import 'package:tally/monitor/supply_statement_export.dart';
import 'package:tally/monitor/supply_statement_sheet.dart';
import 'package:tally/theme/app_theme.dart';

/// The statement a supplier is handed.
void main() {
  SaleLine line({
    required String id,
    required String date,
    String itemCode = 'RCE',
    String description = 'Rice nadu',
    String supplierCode = 'SBT IO BEST',
    double unitPrice = 265,
    double handling = 4,
    double base = 100,
    double merchandise = 26500,
  }) => SaleLine(
    id: id, date: date, receiptNo: 118, seqNo: 1,
    itemCode: itemCode, description: description, supplierCode: supplierCode,
    customerCode: 'KAMAL01',
    pricingBasis: 'kilos', unitPrice: unitPrice,
    handlingQty: handling, handlingUom: 'bag', baseQty: base, baseUom: 'kg',
    merchandiseTotal: merchandise, bagChargeTotal: 0, wageChargeTotal: 0,
    returnedHandling: null, returnedBase: null,
    netHandling: handling, netBase: base, netMerchandise: merchandise,
  );

  Future<void> open(WidgetTester tester, {required bool groupByDate}) async {
    tester.view.physicalSize = const Size(411, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SupplyStatementExportScreen(
          lines: [
            line(id: '1', date: '2026-11-01'),
            line(id: '2', date: '2026-11-01', unitPrice: 270, merchandise: 27000),
            line(id: '3', date: '2026-11-02', itemCode: 'LEK', description: 'Leeks',
                unitPrice: 310, handling: 5, base: 48.5, merchandise: 15035),
          ],
          commissionPercent: 10,
          groupByDate: groupByDate,
          fromDate: '2026-11-01',
          toDate: '2026-11-02',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet carries the goods and the money, and nothing else', (tester) async {
    await open(tester, groupByDate: false);

    // No title over it: the sheet is the statement.
    expect(find.text('SALE STATEMENT'), findsNothing);
    for (final column in ['ITEM', 'UNIT COUNT', 'MEASURED QTY', 'RATE', 'LINE TOTAL']) {
      expect(find.text(column), findsOneWidget);
    }
    expect(find.text('Total unit count'), findsOneWidget);
    expect(find.text('Total measured qty'), findsOneWidget);
    expect(find.text('Merchandise subtotal'), findsOneWidget);
    expect(find.text('Commission 10%'), findsOneWidget);
    expect(find.text('NET PAYABLE'), findsOneWidget);

    // Nothing that names anybody: not the supply code, not the customer, not
    // the bill it went out on.
    expect(find.textContaining('SBT IO BEST'), findsNothing);
    expect(find.textContaining('KAMAL01'), findsNothing);
    expect(find.textContaining('118'), findsNothing);

    // Rice at two rates is two rows; the goods are named, the codes are not.
    expect(find.text('Rice nadu'), findsNWidgets(2));
    expect(find.textContaining('RCE'), findsNothing);
  });

  testWidgets('a day each, and one for the whole range', (tester) async {
    await open(tester, groupByDate: true);

    expect(find.byKey(const ValueKey('statement-tab-0')), findsOneWidget);
    expect(find.text('2026-11-01'), findsWidgets);
    expect(find.text('2026-11-02'), findsWidgets);
    expect(find.text('All together'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-every-statement')), findsOneWidget);

    // The first day is two lots of rice: 26,500 + 27,000 less a tenth.
    expect(find.text('රු. 48,150.00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('statement-tab-1')));
    await tester.pumpAndSettle();
    expect(find.text('Leeks'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('not broken by date, there is one statement and no "send each"', (tester) async {
    await open(tester, groupByDate: false);
    expect(find.byKey(const ValueKey('statement-tab-0')), findsNothing);
    expect(find.byKey(const ValueKey('share-every-statement')), findsNothing);
    expect(find.byKey(const ValueKey('share-this-statement')), findsOneWidget);
  });

  testWidgets('the picture taken is the whole sheet, not the part that fitted', (tester) async {
    tester.view.physicalSize = const Size(411, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The same shape the export screen uses: the sheet drawn at its own width,
    // scaled down only to be looked at.
    final boundary = GlobalKey();
    const group = SupplyCheckGroup(
      label: '2026-11-01',
      rows: [
        SupplyCheckRow(
          itemCode: 'RCE', description: 'Rice nadu', unitPrice: 265, pricingBasis: 'kilos',
          lineCount: 1, handlingQty: 4, handlingUom: 'bag', baseQty: 100, baseUom: 'kg',
          merchandise: 26500,
        ),
      ],
      merchandise: 26500, commission: 2650, netPayable: 23850,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RepaintBoundary(
                  key: boundary,
                  child: const SupplyStatementSheet(
                    heading: '01 Nov 2026', group: group, commissionPercent: 10,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Taking the picture asks the engine for real work, which a widget test
    // fakes away unless it is run for real.
    final png = await tester.runAsync(() => captureSheet(boundary, pixelRatio: 2));
    expect(png, isNotNull);
    final size = _pngSize(png!);
    // 860 wide whatever the phone is, because the sheet is laid out at its own
    // size and the scaling happens above the boundary.
    expect(size.width, SupplyStatementSheet.sheetWidth * 2);
    expect(size.height, greaterThan(300));
  });

  test('the picture is written to disk, because that is what gets shared', () async {
    final directory = await Directory.systemTemp.createTemp('tally-statement');
    addTearDown(() => directory.delete(recursive: true));
    final png = Uint8List.fromList(List<int>.generate(64, (index) => index));

    final shared = await writeSheet(png, 'statement-2026-10-13', directory);

    // Whatever shares it copies from this path, so the bytes must be there.
    final file = File(shared.path);
    expect(file.existsSync(), isTrue);
    expect(await file.readAsBytes(), png);
    expect(shared.path, endsWith('statement-2026-10-13.png'));

    // A heading with awkward characters still makes a file that can be opened.
    final odd = await writeSheet(png, 'statement 01 Nov 2026 → 02 Nov', directory);
    expect(File(odd.path).existsSync(), isTrue);
    expect(odd.path, isNot(contains('→')));
  });
}

/// Width and height out of a PNG's header, so the picture can be measured.
({double width, double height}) _pngSize(Uint8List png) {
  final data = ByteData.sublistView(png);
  return (width: data.getUint32(16).toDouble(), height: data.getUint32(20).toDouble());
}
