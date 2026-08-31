import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tally/data/action_repository.dart';
import 'package:tally/models/tally_action.dart';
import 'package:tally/screens/entry_screen.dart';
import 'package:tally/screens/home_screen.dart';
import 'package:tally/state/tally_store.dart';
import 'package:tally/theme/app_theme.dart';

void main() {
  testWidgets('home shows the big category dock', (tester) async {
    final store = TallyStore(ActionRepository());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Hassle Free Record Keeping.'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
  });

  testWidgets('entry screen number pad builds the amount', (tester) async {
    final store = TallyStore(ActionRepository());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const EntryScreen(type: ActionType.cash),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Received'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('රු. 0.00'), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('5'));
    await tester.tap(find.text('0'));
    await tester.pump();
    expect(find.text('රු. 1,250'), findsOneWidget);

    await tester.tap(find.text('.'));
    await tester.tap(find.text('5'));
    await tester.pump();
    expect(find.text('රු. 1,250.5'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(find.text('රු. 1,250.'), findsOneWidget);
  });

  testWidgets('entry screen does not overflow on a short screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = TallyStore(ActionRepository());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const EntryScreen(type: ActionType.cash),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('රු. 0.00'), findsOneWidget);
  });

  testWidgets('home fits on a short screen', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = TallyStore(ActionRepository());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Cash'), findsOneWidget);
  });

  testWidgets('note category shows a typing area and no number pad', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = TallyStore(ActionRepository());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const EntryScreen(type: ActionType.note),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('What happened?'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('stock entry has item selector and kilo/qty field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1233, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = TallyStore(ActionRepository());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const EntryScreen(type: ActionType.stock),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Select item…'), findsOneWidget);
    expect(find.text('Kilo / Qty'), findsOneWidget);
    expect(find.text('Price'), findsOneWidget);
    expect(find.text('Kg'), findsOneWidget);
    expect(find.text('Pcs'), findsOneWidget);

    await tester.tap(find.text('2'));
    await tester.tap(find.text('5'));
    await tester.pump();
    expect(find.text('25'), findsOneWidget);

    await tester.tap(find.text('Pcs'));
    await tester.tap(find.text('.'));
    await tester.tap(find.text('5'));
    await tester.pump();
    expect(find.text('25.5'), findsOneWidget);

    await tester.tap(find.text('Price'));
    await tester.pump();
    expect(find.text('රු. 0.00'), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.tap(find.text('0'));
    await tester.pump();
    expect(find.text('රු. 10'), findsOneWidget);

    await tester.tap(find.text('Kilo / Qty'));
    await tester.pump();
    expect(find.text('25.5'), findsOneWidget);
  });

  testWidgets('stock entry does not overflow on a short screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = TallyStore(ActionRepository());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const EntryScreen(type: ActionType.stock),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Select item…'), findsOneWidget);
    expect(find.text('Kilo / Qty'), findsOneWidget);
    expect(find.text('Price'), findsOneWidget);
  });

  testWidgets('home shows an animated success banner after recording', (
    tester,
  ) async {
    final store = TallyStore(_FakeRepo());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Hassle Free Record Keeping.'), findsOneWidget);

    await store.record(
      type: ActionType.stock,
      direction: ActionDirection.incoming,
      amount: 0,
      item: 'Potatoes',
      qty: 5,
      unit: 'Kg',
    );
    await tester.pump();

    expect(find.text('Stock in · Potatoes · 5 Kg!'), findsOneWidget);
    expect(find.text('Hassle Free Record Keeping.'), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Stock in · Potatoes · 5 Kg!'), findsNothing);
    expect(find.text('Hassle Free Record Keeping.'), findsOneWidget);
  });

  testWidgets('money formatting with Sinhala rupee symbol', (tester) async {
    expect(Money.format(1250.5), 'රු. 1,250.50');
    expect(Money.format(0), 'රු. 0.00');
    expect(Money.formatInput('12000'), 'රු. 12,000');
    expect(Money.formatInput('12.5'), 'රු. 12.5');
    expect(Money.parseInput('12,500.50'), 12500.5);
  });
}

/// In-memory repository so tests can exercise the real record flow without
/// a device database.
class _FakeRepo extends ActionRepository {
  int _nextId = 1;

  @override
  Future<int> insert(TallyAction action) async => _nextId++;

  @override
  Future<List<TallyAction>> getAll() async => [];
}
