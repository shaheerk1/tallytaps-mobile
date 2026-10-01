import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tally/data/action_repository.dart';
import 'package:tally/models/tally_action.dart';
import 'package:tally/screens/note_screen.dart';
import 'package:tally/screens/app_shell.dart';
import 'package:tally/state/tally_store.dart';
import 'package:tally/theme/app_theme.dart';

void main() {
  testWidgets('the app opens on the notebook, with a way to write', (
    tester,
  ) async {
    final store = TallyStore(ActionRepository());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.light, home: const AppShell()),
      ),
    );
    await tester.pump();

    expect(find.text('TallyTaps'), findsOneWidget);
    expect(find.text('Your notebook is empty.'), findsOneWidget);
    // Writing is the big button; billing is the small one above it.
    expect(find.text('Note'), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
  });

  testWidgets('the note page writes freely and marks nothing by default', (
    tester,
  ) async {
    final store = TallyStore(_FakeRepo());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.light, home: const NoteScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    // Details are offered, never demanded.
    expect(find.text('Money'), findsOneWidget);
    expect(find.text('Goods'), findsOneWidget);
    expect(find.text('Who'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Somebody has to do something'), findsOneWidget);
  });

  testWidgets('a name and a tag typed into the note become its marks', (
    tester,
  ) async {
    final store = TallyStore(_FakeRepo());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.light, home: const NoteScreen()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Took 3 bags @Kamal #credit ');
    await tester.pump();

    expect(find.text('Kamal'), findsOneWidget);
    expect(find.text('#credit'), findsOneWidget);
  });

  testWidgets('the note page fits on a short screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 1500);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = TallyStore(ActionRepository());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.light, home: const NoteScreen()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('home fits on a short screen', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = TallyStore(ActionRepository());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.light, home: const AppShell()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Note'), findsOneWidget);
  });

  testWidgets('a finished note appears in the notebook', (tester) async {
    final store = TallyStore(_FakeRepo());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.light, home: const AppShell()),
      ),
    );
    await tester.pump();

    expect(find.text('Your notebook is empty.'), findsOneWidget);

    await store.recordNote(
      note: 'Took 3 bags to Kamal',
      who: 'Kamal',
      tags: const ['credit'],
    );
    await tester.pump();

    expect(find.text('Took 3 bags to Kamal'), findsOneWidget);
    expect(find.text('Kamal'), findsOneWidget);
    expect(find.text('#credit'), findsOneWidget);
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
/// Stands in for the phone's own storage, so a widget test can write notes
/// without a database behind it.
class _FakeRepo extends ActionRepository {
  int _nextId = 1;

  @override
  Future<int> insert(TallyAction action) async => _nextId++;

  @override
  Future<int> update(TallyAction action) async => 1;

  @override
  Future<int> delete(int id) async => 1;

  @override
  Future<List<TallyAction>> getAll() async => [];
}
