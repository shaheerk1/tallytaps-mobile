import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tally/data/action_repository.dart';
import 'package:tally/monitor/monitor_controller.dart';
import 'package:tally/monitor/supply_check.dart';
import 'package:tally/monitor/supply_check_models.dart';
import 'package:tally/state/tally_store.dart';
import 'package:tally/theme/app_theme.dart';

/// The check screen on a real phone, including the short one a keyboard leaves.
void main() {
  Future<void> open(WidgetTester tester, {required Size size}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = TallyStore(ActionRepository());
    final scope = MonitorScope();
    addTearDown(scope.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ChangeNotifierProvider<MonitorScope>.value(
          value: scope,
          child: Provider<MonitorRepository>.value(
            value: _StubRepository(store),
            child: const Scaffold(body: SupplyCheckView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the lines and their filters fit a full screen', (tester) async {
    await open(tester, size: const Size(411, 866));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('supply-code-filter')), findsOneWidget);
    expect(find.byKey(const ValueKey('sale-line-1')), findsOneWidget);
    expect(find.textContaining('PER'), findsWidgets);
  });

  testWidgets('and the short screen left when the keyboard is up', (tester) async {
    // The height the view was actually given on a phone with the keyboard open.
    // A pinned filter block came to 180 and overflowed this by the 5.7 pixels
    // the device reported.
    await open(tester, size: const Size(411, 174));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('supply-code-filter')), findsOneWidget);

    // And still nothing overflows once the summary bar joins it at that height.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('select-all-lines')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('open-supply-summary')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking lines opens a summary of what they come to', (tester) async {
    await open(tester, size: const Size(411, 866));

    await tester.tap(find.byKey(const ValueKey('select-all-lines')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('open-supply-summary')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-supply-summary')));
    await tester.pumpAndSettle();
    // 5,000 + 3,000 of goods, no commission entered yet.
    expect(find.byKey(const ValueKey('supply-net-payable')), findsOneWidget);
    expect(find.textContaining('8,000.00'), findsWidgets);

    await tester.enterText(find.byKey(const ValueKey('commission-percent')), '10');
    await tester.pumpAndSettle();
    expect(find.textContaining('7,200.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

class _StubRepository extends MonitorRepository {
  _StubRepository(TallyStore store) : super(store: store);

  @override
  Future<SaleLinePage> saleLines(
    MonitorScope scope, {
    List<String> itemCodes = const [],
    List<String> supplierCodes = const [],
    String query = '',
    int limit = 400,
    int offset = 0,
  }) async => SaleLinePage.fromMap(const {
    'total': 2,
    'limit': 400,
    'offset': 0,
    'itemCodes': [
      {'itemCode': 'RCE', 'description': 'Rice', 'lineCount': 1, 'merchandise': 5000},
      {'itemCode': 'LEK', 'description': 'Leeks', 'lineCount': 1, 'merchandise': 3000},
    ],
    'lines': [
      {
        'id': '1', 'date': '2026-11-01', 'receiptNo': 11, 'seqNo': 1,
        'itemCode': 'RCE', 'description': 'Rice', 'supplierCode': 'PER',
        'pricingBasis': 'kilos', 'unitPrice': 100, 'handlingQty': 2, 'handlingUom': 'bag',
        'baseQty': 50, 'baseUom': 'kg', 'merchandiseTotal': 5000,
        'bagChargeTotal': 0, 'wageChargeTotal': 0, 'total': 5000,
        'netHandling': 2, 'netBase': 50, 'netMerchandise': 5000,
      },
      {
        'id': '2', 'date': '2026-11-01', 'receiptNo': 12, 'seqNo': 1,
        'itemCode': 'LEK', 'description': 'Leeks', 'supplierCode': 'SIL',
        'pricingBasis': 'kilos', 'unitPrice': 300, 'handlingQty': 1, 'handlingUom': 'bag',
        'baseQty': 10, 'baseUom': 'kg', 'merchandiseTotal': 3000,
        'bagChargeTotal': 0, 'wageChargeTotal': 0, 'total': 3000,
        'netHandling': 1, 'netBase': 10, 'netMerchandise': 3000,
      },
    ],
  });
}
