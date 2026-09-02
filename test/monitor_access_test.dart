import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tally/data/action_repository.dart';
import 'package:tally/screens/home_screen.dart';
import 'package:tally/monitor/monitor_controller.dart';
import 'package:tally/monitor/monitor_models.dart';
import 'package:tally/monitor/monitor_operations.dart';
import 'package:tally/monitor/monitor_widgets.dart';
import 'package:tally/services/sync_config_service.dart';
import 'package:tally/services/sync_service.dart';
import 'package:tally/state/tally_store.dart';
import 'package:tally/theme/app_theme.dart';

/// Business Monitor access is granted by the host and re-checked by the server
/// on every request. The app only decides whether to *draw* the entry point, so
/// what matters here is that it stays hidden unless the server says otherwise,
/// and that a withdrawal can actually be written back.

void main() {
  group('device session', () {
    test('grants the monitor only when the server says so', () {
      final session = DeviceSession.fromMap({
        'device': {'name': 'Owner phone', 'hostCode': 'TH-1', 'hostName': 'Main'},
        'capabilities': {'businessMonitor': true},
      });
      expect(session.businessMonitor, isTrue);
      expect(session.deviceName, 'Owner phone');
      expect(session.hostCode, 'TH-1');
    });

    test('withholds the monitor for an ordinary recording device', () {
      final session = DeviceSession.fromMap({
        'device': {'name': 'Shop phone'},
        'capabilities': {'businessMonitor': false},
      });
      expect(session.businessMonitor, isFalse);
    });

    test('a malformed or truncated answer never grants access', () {
      expect(DeviceSession.fromMap({}).businessMonitor, isFalse);
      expect(
        DeviceSession.fromMap({'capabilities': 'yes'}).businessMonitor,
        isFalse,
      );
      // A string is not a true boolean: only an explicit true opens the monitor.
      expect(
        DeviceSession.fromMap({
          'capabilities': {'businessMonitor': 'true'},
        }).businessMonitor,
        isFalse,
      );
    });
  });

  group('stored connection', () {
    SyncConnection connection({bool monitor = false}) => SyncConnection(
      serverUrl: 'https://host.example',
      hostCode: 'TH-1',
      deviceId: 'device-1',
      status: ConnectionStatus.connected,
      deviceToken: 'token',
      monitorAccess: monitor,
    );

    test('the grant survives being saved and read back', () {
      final restored = SyncConnection.fromMap(
        connection(monitor: true).toMap(),
      );
      expect(restored.monitorAccess, isTrue);
    });

    test('a connection stored before this feature defaults to no access', () {
      final legacy = SyncConnection.fromMap({
        'serverUrl': 'https://host.example',
        'hostCode': 'TH-1',
        'deviceId': 'device-1',
        'status': 'connected',
        'deviceToken': 'token',
      });
      expect(legacy.monitorAccess, isFalse);
    });

    test('withdrawing access clears the flag, which copyWith cannot do', () {
      final granted = connection(monitor: true);
      expect(granted.withMonitorAccess(false).monitorAccess, isFalse);
      // copyWith carries the grant forward untouched, so it is never the path
      // used to revoke.
      expect(granted.copyWith(deliveryScope: 'selected').monitorAccess, isTrue);
    });
  });

  testWidgets('home hides the monitor until a host grants it', (tester) async {
    final store = TallyStore(ActionRepository());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pump();

    expect(store.monitorAccess, isFalse);
    expect(find.text('Business Monitor'), findsNothing);
    // The recording flow is untouched by the feature.
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Create a quick bill'), findsOneWidget);
  });

  testWidgets('monitor sub-routes retain repository and shared filter providers', (tester) async {
    final store = TallyStore(ActionRepository());
    final scope = MonitorScope();
    addTearDown(scope.dispose);
    final repository = MonitorRepository(store: store);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<MonitorScope>.value(
          value: scope,
          child: Provider<MonitorRepository>.value(
            value: repository,
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => pushMonitorRoute(
                    context,
                    Builder(
                      builder: (routeContext) {
                        routeContext.read<MonitorRepository>();
                        routeContext.watch<MonitorScope>();
                        return const Scaffold(body: Text('route-scope-ok'));
                      },
                    ),
                  ),
                  child: const Text('open monitor detail'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open monitor detail'));
    await tester.pumpAndSettle();
    expect(find.text('route-scope-ok'), findsOneWidget);
  });

  testWidgets('receivables offer calling only when a mobile number exists', (
    tester,
  ) async {
    final store = TallyStore(ActionRepository());
    final scope = MonitorScope();
    addTearDown(scope.dispose);
    final repository = _ReceivablesRepository(store);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ChangeNotifierProvider<MonitorScope>.value(
          value: scope,
          child: Provider<MonitorRepository>.value(
            value: repository,
            child: const MonitorReceivablesScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('077 123 4567'), findsOneWidget);
    expect(find.byIcon(Icons.call_rounded), findsOneWidget);
    expect(find.byTooltip('Call Nimal Stores'), findsOneWidget);
  });
}

class _ReceivablesRepository extends MonitorRepository {
  _ReceivablesRepository(TallyStore store) : super(store: store);

  @override
  Future<List<MonitorReceivable>> receivables(MonitorScope scope) async => [
    const MonitorReceivable(
      customerCode: 'C001',
      customerName: 'Nimal Stores',
      customerMobile: '077 123 4567',
      invoiceCount: 2,
      balance: 2500,
      oldest: '2026-08-30',
    ),
    const MonitorReceivable(
      customerCode: 'C002',
      customerName: 'No Phone Shop',
      invoiceCount: 1,
      balance: 500,
      oldest: '2026-09-01',
    ),
  ];
}
