import 'package:flutter/foundation.dart';

import '../services/sync_config_service.dart';
import '../services/sync_service.dart';
import '../state/tally_store.dart';
import 'monitor_models.dart';

/// The period and terminal every monitor screen reads through.
///
/// Screens listen to this rather than owning their own filters, so changing the
/// range once updates the whole section.
enum RangePreset { today, yesterday, week, month, custom }

extension RangePresetLabel on RangePreset {
  String get label => switch (this) {
    RangePreset.today => 'Today',
    RangePreset.yesterday => 'Yesterday',
    RangePreset.week => 'Last 7 days',
    RangePreset.month => 'This month',
    RangePreset.custom => 'Custom',
  };
}

String _iso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

class MonitorScope extends ChangeNotifier {
  MonitorScope() {
    applyPreset(RangePreset.today);
  }

  RangePreset _preset = RangePreset.today;
  late DateTime _from;
  late DateTime _to;
  String? _nodeId;
  MonitorFleet _fleet = MonitorFleet.empty;

  RangePreset get preset => _preset;
  DateTime get from => _from;
  DateTime get to => _to;
  String get fromIso => _iso(_from);
  String get toIso => _iso(_to);
  String? get nodeId => _nodeId;
  MonitorFleet get fleet => _fleet;

  /// A stable value screens can watch to know the filters moved.
  String get key => '${_iso(_from)}|${_iso(_to)}|${_nodeId ?? 'all'}';

  bool get isSingleDay => _iso(_from) == _iso(_to);

  String get rangeLabel {
    if (_preset != RangePreset.custom) return _preset.label;
    if (isSingleDay) return _iso(_from);
    return '${_iso(_from)} → ${_iso(_to)}';
  }

  String get nodeLabel {
    if (_nodeId == null) return 'All POS systems';
    return _fleet.nodes
        .firstWhere(
          (node) => node.id == _nodeId,
          orElse: () => const MonitorNode(id: '', name: 'Selected POS'),
        )
        .name;
  }

  void applyPreset(RangePreset preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _preset = preset;
    switch (preset) {
      case RangePreset.today:
        _from = today;
        _to = today;
      case RangePreset.yesterday:
        _from = today.subtract(const Duration(days: 1));
        _to = _from;
      case RangePreset.week:
        _from = today.subtract(const Duration(days: 6));
        _to = today;
      case RangePreset.month:
        _from = DateTime(now.year, now.month, 1);
        _to = today;
      case RangePreset.custom:
        break;
    }
    notifyListeners();
  }

  void applyCustom(DateTime from, DateTime to) {
    _preset = RangePreset.custom;
    _from = from.isAfter(to) ? to : from;
    _to = from.isAfter(to) ? from : to;
    notifyListeners();
  }

  void selectNode(String? nodeId) {
    if (_nodeId == nodeId) return;
    _nodeId = nodeId;
    notifyListeners();
  }

  void setFleet(MonitorFleet fleet) {
    _fleet = fleet;
    if (_nodeId != null && !fleet.nodes.any((node) => node.id == _nodeId)) {
      _nodeId = null;
    }
    notifyListeners();
  }
}

/// Reads the Business Monitor API.
///
/// The server re-checks this device's grant on every call. When it refuses, the
/// store is told at once so the whole section disappears rather than sitting
/// there showing stale numbers.
class MonitorRepository {
  MonitorRepository({required TallyStore store, SyncService? service})
    : _store = store,
      _service = service ?? SyncService();

  final TallyStore _store;
  final SyncService _service;

  SyncConnection get _connection {
    final connection = _store.connection;
    if (connection == null || !connection.isConnected) {
      throw const SyncFailure('Connect this device to its host first.');
    }
    return connection;
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String> query = const {},
  }) async {
    try {
      return await _service.monitorGet(_connection, path, query: query);
    } on MonitorAccessRevoked {
      await _store.onMonitorAccessRevoked();
      rethrow;
    }
  }

  Map<String, String> _scoped(MonitorScope scope, [Map<String, String> extra = const {}]) => {
    'from': scope.fromIso,
    'to': scope.toIso,
    if (scope.nodeId != null) 'nodeId': scope.nodeId!,
    ...extra,
  };

  Map<String, String> _node(MonitorScope scope, [Map<String, String> extra = const {}]) => {
    if (scope.nodeId != null) 'nodeId': scope.nodeId!,
    ...extra,
  };

  Future<MonitorFleet> fleet() async =>
      MonitorFleet.fromMap(await _get('/terminals'));

  Future<MonitorOverview> overview(MonitorScope scope) async =>
      MonitorOverview.fromMap(await _get('/overview', query: _scoped(scope)));

  Future<MonitorSales> sales(MonitorScope scope, String groupBy) async =>
      MonitorSales.fromMap(
        await _get('/sales', query: _scoped(scope, {'groupBy': groupBy})),
      );

  Future<MonitorInvoicePage> invoices(
    MonitorScope scope, {
    String query = '',
    bool outstandingOnly = false,
    int offset = 0,
  }) async => MonitorInvoicePage.fromMap(
    await _get(
      '/invoices',
      query: _scoped(scope, {
        if (query.isNotEmpty) 'q': query,
        if (outstandingOnly) 'outstandingOnly': 'true',
        'offset': '$offset',
      }),
    ),
  );

  Future<MonitorInvoiceDetail> invoice(String nodeId, String invoiceId) async =>
      MonitorInvoiceDetail.fromMap(await _get('/invoices/$nodeId/$invoiceId'));

  Future<MonitorCash> cash(MonitorScope scope) async =>
      MonitorCash.fromMap(await _get('/cash', query: _scoped(scope)));

  Future<List<MonitorReceivable>> receivables(MonitorScope scope) async =>
      parseRows(
        await _get('/receivables', query: _node(scope)),
        MonitorReceivable.fromMap,
      );

  Future<MonitorCheques> cheques(MonitorScope scope, {String status = ''}) async =>
      MonitorCheques.fromMap(
        await _get(
          '/cheques',
          query: _node(scope, {if (status.isNotEmpty) 'status': status}),
        ),
      );

  Future<List<MonitorStockItem>> stock(
    MonitorScope scope, {
    String query = '',
  }) async => parseRows(
    await _get('/stock', query: _node(scope, {if (query.isNotEmpty) 'q': query})),
    MonitorStockItem.fromMap,
  );

  Future<List<MonitorLot>> lots(
    MonitorScope scope, {
    String productKey = '',
  }) async => parseRows(
    await _get(
      '/lots',
      query: _node(scope, {if (productKey.isNotEmpty) 'productKey': productKey}),
    ),
    MonitorLot.fromMap,
  );

  Future<List<MonitorGrn>> goodsReceipts(MonitorScope scope) async =>
      parseRows(
        await _get('/goods-receipts', query: _scoped(scope)),
        MonitorGrn.fromMap,
      );
}
