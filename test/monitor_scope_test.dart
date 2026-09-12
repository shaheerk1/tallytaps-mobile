import 'package:flutter_test/flutter_test.dart';
import 'package:tally/monitor/monitor_controller.dart';
import 'package:tally/monitor/monitor_models.dart';

/// The monitor reads a business the way its owner thinks of it: shops first,
/// counters inside them, and returned bills treated as reversed sales.
void main() {
  final fleet = MonitorFleet.fromMap(const {
    'nodes': [
      {'id': 'node-1', 'name': 'Shop PC'},
    ],
    'locations': [
      {
        'locCode': 'KST01',
        'name': 'Khan Store',
        'businessCode': 'KHANSTORE',
        'terminals': [
          {'macCode': 'T1', 'name': 'Front counter', 'nodeId': 'node-1'},
          {'macCode': 'T2', 'name': 'Back counter', 'nodeId': 'node-1'},
        ],
      },
      {
        'locCode': 'KRT01',
        'name': 'Khan Retail',
        'businessCode': 'KHANRETAIL',
        'terminals': [
          {'macCode': 'T1', 'name': 'Counter', 'nodeId': 'node-1'},
        ],
      },
    ],
    'terminals': [
      {'nodeId': 'node-1', 'locCode': 'KST01', 'macCode': 'T1', 'name': 'Front counter'},
    ],
    'openDays': [],
  });

  test('a host is read as shops and the counters inside them', () {
    expect(fleet.locations.length, 2);
    expect(fleet.locationOf('KST01')!.name, 'Khan Store');
    expect(fleet.locationOf('KST01')!.counters.length, 2);
    expect(fleet.locationOf('NOPE'), isNull);
  });

  test('the place can be the whole business, one shop, or one counter', () {
    final scope = MonitorScope()..setFleet(fleet);
    expect(scope.locCode, isNull);
    expect(scope.placeLabel, 'All shops');

    scope.selectPlace(locCode: 'KST01');
    expect(scope.placeLabel, 'Khan Store');
    expect(scope.placeKey, 'KST01|all');

    scope.selectPlace(locCode: 'KST01', macCode: 'T2');
    expect(scope.placeLabel, 'Khan Store · Back counter');
    expect(scope.key, contains('KST01|T2'));

    scope.selectPlace();
    expect(scope.placeKey, 'all|all');
  });

  test('a counter cannot stay selected without its shop', () {
    final scope = MonitorScope()
      ..setFleet(fleet)
      ..selectPlace(locCode: 'KST01', macCode: 'T2');

    // The shop is gone from the host: the whole place selection resets.
    scope.setFleet(MonitorFleet.fromMap(const {
      'nodes': [],
      'locations': [
        {'locCode': 'KRT01', 'name': 'Khan Retail', 'terminals': []},
      ],
      'terminals': [],
      'openDays': [],
    }));
    expect(scope.locCode, isNull);
    expect(scope.macCode, isNull);
  });

  test('picking a shop drops the counter that belonged to another one', () {
    final scope = MonitorScope()
      ..setFleet(fleet)
      ..selectPlace(locCode: 'KST01', macCode: 'T2')
      ..selectPlace(locCode: 'KRT01');
    expect(scope.macCode, isNull);
  });

  test('a bill knows what came back, and what it is now worth', () {
    final page = MonitorInvoicePage.fromMap(const {
      'total': 3,
      'netTotal': 1400.0,
      'netCollected': 1200.0,
      'returnedTotal': 600.0,
      'offset': 0,
      'limit': 40,
      'rows': [
        {
          'invoiceNumber': 'INV-1', 'grandTotal': 1000.0, 'paidTotal': 1000.0,
          'returnedTotal': 0, 'returnedCashTotal': 0, 'refundStatus': 'none',
        },
        {
          'invoiceNumber': 'INV-2', 'grandTotal': 600.0, 'paidTotal': 600.0,
          'returnedTotal': 200.0, 'returnedCashTotal': 200.0, 'refundStatus': 'partial',
        },
        {
          'invoiceNumber': 'INV-3', 'grandTotal': 400.0, 'paidTotal': 400.0,
          'returnedTotal': 400.0, 'returnedCashTotal': 400.0, 'refundStatus': 'full',
        },
      ],
    });

    expect(page.netTotal, 1400.0);
    expect(page.hasReturns, isTrue);

    final whole = page.rows[0];
    expect(whole.isReturned, isFalse);
    expect(whole.netTotal, 1000.0);

    final part = page.rows[1];
    expect(part.isReturned, isTrue);
    expect(part.isFullyReturned, isFalse);
    expect(part.returnLabel, 'Part returned');
    expect(part.netTotal, 400.0);
    expect(part.netCollected, 400.0);

    final reversed = page.rows[2];
    expect(reversed.isFullyReturned, isTrue);
    expect(reversed.returnLabel, 'Returned');
    expect(reversed.netTotal, 0.0);
  });

  test('sales groups and headline figures are already net of returns', () {
    final sales = MonitorSales.fromMap(const {
      'groupBy': 'day',
      'label': 'Business day',
      'rows': [
        {
          'bucket': '2026-09-12', 'invoiceCount': 4, 'gross': 5000.0, 'net': 4400.0,
          'collected': 4100.0, 'credit': 300.0, 'returned': 600.0, 'refundCount': 1,
        },
      ],
      'items': [],
    });
    final bucket = sales.buckets.single;
    expect(bucket.net, 4400.0);
    expect(bucket.hasReturns, isTrue);

    final overview = MonitorOverview.fromMap(const {
      'sales': {'invoiceCount': 4, 'gross': 5000.0, 'net': 4400.0, 'collected': 4100.0},
      'refunds': {'count': 1, 'total': 600.0, 'cashReturned': 500.0},
      'outstanding': {}, 'drawers': {}, 'customerAdvance': {},
    });
    expect(overview.net, 4400.0);
    expect(overview.collected, 4100.0);
    expect(overview.cashReturned, 500.0);
  });
}
