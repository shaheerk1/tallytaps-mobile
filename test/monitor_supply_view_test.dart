import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tally/data/action_repository.dart';
import 'package:tally/monitor/monitor_controller.dart';
import 'package:tally/monitor/monitor_supply.dart';
import 'package:tally/monitor/monitor_supply_models.dart';
import 'package:tally/monitor/monitor_widgets.dart';
import 'package:tally/state/tally_store.dart';
import 'package:tally/theme/app_theme.dart';

/// The supply section's own controls, on the narrowest phone the shop uses.
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
            child: const Scaffold(body: MonitorSupplyTab()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('all five views keep their names on a narrow phone', (tester) async {
    // 320 logical pixels: the smallest screen the shop is likely to hold.
    await open(tester, size: const Size(320, 640));

    expect(tester.takeException(), isNull);
    for (final label in ['Deliveries', 'On floor', 'Statements', 'Owed', 'Check']) {
      expect(find.text(label), findsOneWidget, reason: '$label must still be readable');
    }
  });

  testWidgets('the views wrap onto a second line rather than being squeezed', (tester) async {
    await open(tester, size: const Size(320, 640));

    final picker = tester.getSize(find.byType(MonitorViewPicker));
    final onePill = tester.getSize(find.text('Deliveries'));
    // Two rows of pills, not one squeezed row.
    expect(picker.height, greaterThan(onePill.height * 3));
    expect(picker.width, lessThanOrEqualTo(320));

    // The first and last views sit on different rows at this width.
    expect(
      tester.getTopLeft(find.text('Check')).dy,
      greaterThan(tester.getTopLeft(find.text('Deliveries')).dy),
    );
  });

  testWidgets('and sit on one line when there is room', (tester) async {
    await open(tester, size: const Size(900, 640));
    expect(
      tester.getTopLeft(find.text('Check')).dy,
      equals(tester.getTopLeft(find.text('Deliveries')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving to another view takes the person there', (tester) async {
    await open(tester, size: const Size(411, 866));
    expect(find.text('Goods received'), findsOneWidget);

    await tester.tap(find.text('On floor'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Search item, lot code or supplier'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _StubRepository extends MonitorRepository {
  _StubRepository(TallyStore store) : super(store: store);

  @override
  Future<List<MonitorGoodsReceipt>> goodsReceipts(
    MonitorScope scope, {
    String status = '',
  }) async => [];

  @override
  Future<List<MonitorActiveLot>> activeLots(
    MonitorScope scope, {
    String query = '',
    bool includeEmpty = false,
  }) async => [];
}
