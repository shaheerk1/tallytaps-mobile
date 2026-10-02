import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tally/data/action_repository.dart';
import 'package:tally/models/mobile_bill.dart';
import 'package:tally/screens/mobile_billing_screen.dart';
import 'package:tally/state/tally_store.dart';
import 'package:tally/theme/app_theme.dart';

void main() {
  testWidgets('price editor closes without reusing a disposed controller', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = _BillingStore();
    await tester.pumpWidget(
      ChangeNotifierProvider<TallyStore>.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const MobileBillingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('billing-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('billing-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review-line-0')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('line-selling-price')),
      '12',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('line-price-reason')),
      'Customer rate',
    );
    await tester.tap(find.byKey(const ValueKey('line-editor-save')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('රු. 12.00 per piece'), findsOneWidget);
  });

  testWidgets('dual UoM item asks for configured units and applies charges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = _BillingStore(dualOnly: true);
    await tester.pumpWidget(
      ChangeNotifierProvider<TallyStore>.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const MobileBillingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('billing-item-2')));
    await tester.pumpAndSettle();
    expect(find.text('Unit Count'), findsOneWidget);
    expect(find.text('Measured Qty'), findsOneWidget);
    expect(find.text('boxes'), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('line-handling-quantity')),
      '2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('line-measured-quantity')),
      '5',
    );
    await tester.pump();
    expect(find.text('Use item · රු. 59.00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('line-editor-save')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('2 boxes · 5 kg'), findsOneWidget);
  });

  testWidgets('a plain item can be billed on two lines of its own', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _open(tester, _BillingStore());

    // One tap bills it; tapping the item again is one more of the same line.
    await tester.tap(find.byKey(const ValueKey('billing-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Screws'));
    await tester.pumpAndSettle();
    expect(find.text('2 piece'), findsOneWidget);

    // Asking for another line keeps them apart.
    await tester.tap(find.byKey(const ValueKey('billing-again-1')));
    await tester.pumpAndSettle();
    expect(find.text('1 · 2 piece'), findsOneWidget);
    expect(find.text('2 · 1 piece'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('billing-review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-line-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-line-1')), findsOneWidget);
    expect(find.text('Line 1 of 2'), findsOneWidget);
    expect(find.text('Line 2 of 2'), findsOneWidget);
    expect(find.text('Save bill · රු. 30.00'), findsOneWidget);
  });

  testWidgets('the same weighed item takes a line per weighing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _open(tester, _BillingStore(dualOnly: true));

    await tester.tap(find.byKey(const ValueKey('billing-item-2')));
    await tester.pumpAndSettle();
    await _fillLine(tester, measured: '5', count: '2');

    // A second weighing of the same item, not a bigger first one.
    await tester.tap(find.byKey(const ValueKey('billing-again-2')));
    await tester.pumpAndSettle();
    await _fillLine(tester, measured: '7', count: '3');

    expect(find.text('1 · 2 boxes · 5 kg'), findsOneWidget);
    expect(find.text('2 · 3 boxes · 7 kg'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('billing-review')));
    await tester.pumpAndSettle();
    // 5kg: 50 + 4 packaging + 5 wage = 59. 7kg: 70 + 6 + 7 = 83.
    expect(find.text('Save bill · රු. 142.00'), findsOneWidget);
  });

  testWidgets('a weighed line asks for the weight first, and Enter walks on', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _open(tester, _BillingStore(dualOnly: true));
    await tester.tap(find.byKey(const ValueKey('billing-item-2')));
    await tester.pumpAndSettle();

    final measuredField = find.byKey(const ValueKey('line-measured-quantity'));
    final countField = find.byKey(const ValueKey('line-handling-quantity'));
    // Measured Qty is the first field on the row, and holds the focus.
    expect(
      tester.getTopLeft(measuredField).dx,
      lessThan(tester.getTopLeft(countField).dx),
    );
    expect(_focusOf(tester, measuredField).hasFocus, isTrue);

    await tester.enterText(measuredField, '5');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(_focusOf(tester, countField).hasFocus, isTrue);

    // Nothing is left to fill, so Enter keeps the line.
    await tester.enterText(countField, '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('line-editor-save')), findsNothing);
    expect(find.text('2 boxes · 5 kg'), findsOneWidget);
  });
}

Future<void> _open(WidgetTester tester, TallyStore store) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<TallyStore>.value(
      value: store,
      child: MaterialApp(
        theme: AppTheme.light,
        home: const MobileBillingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillLine(
  WidgetTester tester, {
  required String measured,
  required String count,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('line-measured-quantity')),
    measured,
  );
  await tester.enterText(
    find.byKey(const ValueKey('line-handling-quantity')),
    count,
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('line-editor-save')));
  await tester.pumpAndSettle();
}

FocusNode _focusOf(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).focusNode!;

class _BillingStore extends TallyStore {
  _BillingStore({this.dualOnly = false}) : super(ActionRepository());

  final bool dualOnly;

  static const _node = PosCatalogNode(
    id: 'node-1',
    nickname: 'Main POS',
    itemCount: 1,
  );

  static const _simple = CatalogItem(
    nodeId: 'node-1',
    sourceProductKey: '1',
    name: 'Screws',
    unitPrice: 10,
    attributes: {
      'handling_uom': 'piece',
      'pricing_basis': 'qty',
      'quantity_step': 1,
      'price_override_allowed': 1,
      'price_override_reason_required': 1,
    },
  );

  static const _dual = CatalogItem(
    nodeId: 'node-1',
    sourceProductKey: '2',
    name: 'Produce box',
    unitPrice: 10,
    attributes: {
      'handling_uom': 'boxes',
      'base_uom': 'kg',
      'dual_uom_enabled': 1,
      'requires_kilos': 1,
      'pricing_basis': 'kilos',
      'bag_charge': 2,
      'wage_charge': 1,
      'wage_basis': 'kilos',
    },
  );

  @override
  Future<List<PosCatalogNode>> loadPosNodes({bool refresh = true}) async => [
    _node,
  ];

  @override
  Future<List<CatalogItem>> loadCatalog(
    String nodeId, {
    bool refresh = true,
  }) async => [dualOnly ? _dual : _simple];
}
