import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tally/data/action_repository.dart';
import 'package:tally/data/billing_repository.dart';
import 'package:tally/models/mobile_bill.dart';
import 'package:tally/screens/history_screen.dart';
import 'package:tally/state/tally_store.dart';
import 'package:tally/theme/app_theme.dart';

void main() {
  testWidgets('history shows a pending mobile bill and its details', (
    tester,
  ) async {
    final store = TallyStore(
      ActionRepository(),
      billingRepository: _MemoryBillingRepository(),
    );
    await store.submitMobileBill(
      MobileBill(
        clientBillId: 'mobile-bill-1',
        catalogPosNodeId: 'node-1',
        deliveryScope: 'all',
        targetPosNodeIds: const [],
        lines: [
          MobileBillLine(
            item: const CatalogItem(
              nodeId: 'node-1',
              sourceProductKey: '10',
              name: 'Potato sack',
              unitPrice: 100,
              attributes: {'handling_uom': 'bag'},
            ),
            quantity: 2,
          ),
        ],
        paymentMethod: 'cash',
        customerName: 'Field customer',
        createdAt: DateTime.now(),
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const HistoryScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Bills 1'));
    await tester.pumpAndSettle();
    expect(find.text('Field customer'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);

    await tester.tap(find.text('Field customer'));
    await tester.pumpAndSettle();
    expect(find.text('Mobile bill'), findsOneWidget);
    expect(find.text('Potato sack'), findsOneWidget);
    expect(find.text('Waiting to sync'), findsOneWidget);
  });
}

class _MemoryBillingRepository extends BillingRepository {
  @override
  Future<void> saveBill(MobileBill bill) async {}

  @override
  Future<int> pendingCount() async => 1;
}
