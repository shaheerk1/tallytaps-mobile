import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/monitor/monitor_widgets.dart';
import 'package:tally/theme/app_theme.dart';

/// What every monitor card does while it waits, and when the answer never came.
void main() {
  testWidgets('a failed read offers to try again, and trying again works', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MonitorAsync<String>(
            reloadKey: 'once',
            load: () async {
              attempts += 1;
              if (attempts == 1) throw Exception('the host is away');
              return 'it worked';
            },
            builder: (context, value) => Text(value),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load this'), findsOneWidget);
    expect(find.textContaining('the host is away'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    // Retrying must not throw: setState is handed a Future if the closure that
    // sets it is written with an arrow, and Flutter refuses that.
    expect(tester.takeException(), isNull);
    expect(attempts, 2);
    expect(find.text('it worked'), findsOneWidget);
  });

  testWidgets('a reload key that moves asks again', (tester) async {
    var attempts = 0;
    Widget page(String key) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MonitorAsync<String>(
          reloadKey: key,
          load: () async {
            attempts += 1;
            return 'read $attempts';
          },
          builder: (context, value) => Text(value),
        ),
      ),
    );

    await tester.pumpWidget(page('monday'));
    await tester.pumpAndSettle();
    expect(find.text('read 1'), findsOneWidget);

    await tester.pumpWidget(page('tuesday'));
    await tester.pumpAndSettle();
    expect(find.text('read 2'), findsOneWidget);

    // The same key again is the same answer, not another read.
    await tester.pumpWidget(page('tuesday'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
}
