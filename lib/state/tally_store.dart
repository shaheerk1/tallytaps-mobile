import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/action_repository.dart';
import '../data/billing_repository.dart';
import '../models/mobile_bill.dart';
import '../models/media_attachment.dart';
import '../models/tally_action.dart';
import '../services/sync_config_service.dart';
import '../services/sync_service.dart';

/// App-wide state. Holds every recorded action in memory after each change
/// so the UI always reflects what is on disk.
class TallyStore extends ChangeNotifier {
  TallyStore(
    this._repo, {
    SyncService? syncService,
    BillingRepository? billingRepository,
  }) : _syncService = syncService ?? SyncService(),
       _billingRepository = billingRepository ?? BillingRepository();

  final ActionRepository _repo;
  final SyncService _syncService;
  final BillingRepository _billingRepository;

  List<TallyAction> _actions = [];
  bool _loading = true;
  TallyAction? _lastRecorded;
  int _lastRecordedNonce = 0;
  SyncConnection? _connection;
  bool _syncing = false;
  bool _syncingBills = false;
  String? _lastSyncError;
  int _pendingBillCount = 0;
  List<MobileBill> _mobileBills = [];

  List<TallyAction> get actions => _actions;
  bool get loading => _loading;
  SyncConnection? get connection => _connection;
  bool get syncing => _syncing || _syncingBills;
  String? get lastSyncError => _lastSyncError;
  bool get isConnected => _connection?.isConnected ?? false;
  int get pendingBillCount => _pendingBillCount;
  List<MobileBill> get mobileBills => _mobileBills;

  /// Whether this device may open the Business Monitor.
  ///
  /// Only the host grants this, and the server re-checks it on every monitor
  /// request. The stored copy decides whether the entry point is drawn before
  /// the first call answers; it is never treated as authorization.
  bool get monitorAccess => _connection?.monitorAccess ?? false;

  /// The most recently recorded action, shown as a success banner on home.
  TallyAction? get lastRecorded => _lastRecorded;

  /// Bumped on every change so widgets can replay the success animation.
  int get lastRecordedNonce => _lastRecordedNonce;

  List<TallyAction> get unsynced => _actions.where((a) => !a.synced).toList();

  /// Money actions created today, newest first. Stock is excluded — its
  /// amount is the item price, not cash received/paid.
  List<TallyAction> get today => _actions.where((a) {
    final now = DateTime.now();
    final s = DateTime(a.createdAt.year, a.createdAt.month, a.createdAt.day);
    final t = DateTime(now.year, now.month, now.day);
    return s == t && a.type != ActionType.stock;
  }).toList();

  double todayIncoming() => today
      .where((a) => a.direction == ActionDirection.incoming)
      .fold(0, (sum, a) => sum + a.amount);

  double todayOutgoing() => today
      .where((a) => a.direction == ActionDirection.outgoing)
      .fold(0, (sum, a) => sum + a.amount);

  Future<void> refresh() async {
    _actions = await _repo.getAll();
    _connection = await _syncService.loadConnection();
    _pendingBillCount = await _billingRepository.pendingCount();
    _mobileBills = await _billingRepository.bills();
    _loading = false;
    notifyListeners();
    if (isConnected && unsynced.isNotEmpty) {
      unawaited(syncPending());
    }
    if (isConnected && _pendingBillCount > 0) unawaited(syncPendingBills());
    if (isConnected) unawaited(refreshDeviceSession());
  }

  /// Re-reads what the host allows this device to do. Runs on launch and
  /// whenever the connection screen opens, so a privilege granted or withdrawn
  /// in the portal reaches the phone without re-pairing.
  Future<void> refreshDeviceSession() async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return;
    try {
      final session = await _syncService.fetchSession(connection);
      await _applyMonitorAccess(session.businessMonitor);
    } on SyncFailure {
      // Offline or a transient server problem: keep whatever is stored rather
      // than hiding a monitor the host has not actually withdrawn.
    } on MonitorAccessRevoked {
      await _applyMonitorAccess(false);
    }
  }

  /// Called when a monitor request is refused, so the view disappears the
  /// moment the host withdraws access rather than at the next launch.
  Future<void> onMonitorAccessRevoked() => _applyMonitorAccess(false);

  Future<void> _applyMonitorAccess(bool granted) async {
    final connection = _connection;
    if (connection == null || connection.monitorAccess == granted) return;
    final updated = connection.withMonitorAccess(granted);
    await _syncService.saveConnection(updated);
    _connection = updated;
    notifyListeners();
  }

  Future<TallyAction> record({
    required ActionType type,
    required ActionDirection direction,
    required double amount,
    String? item,
    double? qty,
    String? unit,
    String? note,
    String? voicePath,
    List<String> imagePaths = const [],
  }) async {
    final action = TallyAction(
      type: type,
      direction: direction,
      amount: amount,
      item: item,
      qty: qty,
      unit: unit,
      note: (note == null || note.trim().isEmpty) ? null : note.trim(),
      voicePath: voicePath,
      imagePaths: imagePaths,
      mediaAssets: _buildMediaAssets(voicePath, imagePaths),
      createdAt: DateTime.now(),
    );
    final id = await _repo.insert(action);
    action.id = id;
    _actions.insert(0, action);
    _lastRecorded = action;
    _lastRecordedNonce++;
    notifyListeners();
    if (isConnected) unawaited(syncPending());
    return action;
  }

  List<MediaAttachment> _buildMediaAssets(
    String? voicePath,
    List<String> imagePaths,
  ) {
    final uuid = const Uuid();
    return [
      for (final path in imagePaths)
        MediaAttachment(
          clientMediaId: uuid.v4(),
          localPath: path,
          type: MediaAttachmentType.image,
        ),
      if (voicePath != null && voicePath.isNotEmpty)
        MediaAttachment(
          clientMediaId: uuid.v4(),
          localPath: voicePath,
          type: MediaAttachmentType.audio,
        ),
    ];
  }

  /// Clears the home success banner after it has animated away.
  void clearLastRecorded() {
    if (_lastRecorded == null) return;
    _lastRecorded = null;
    _lastRecordedNonce++;
    notifyListeners();
  }

  Future<List<String>> loadItems() => _repo.getItems();

  Future<String> addItem(String name) => _repo.addItem(name);

  Future<void> deleteAction(TallyAction action) async {
    if (action.id != null) {
      await _repo.delete(action.id!);
    }
    _actions.removeWhere((a) => a.id == action.id);
    notifyListeners();
  }

  Future<void> markSynced(int id) async {
    final index = _actions.indexWhere((a) => a.id == id);
    if (index == -1) return;
    await _repo.markSynced(id, DateTime.now());
    _actions[index].synced = true;
    _actions[index].syncedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> startPairing({
    required String serverUrl,
    required String hostCode,
  }) async {
    _connection = await _syncService.requestPairing(
      serverUrl: serverUrl,
      hostCode: hostCode,
    );
    _lastSyncError = null;
    notifyListeners();
  }

  Future<void> checkPairing() async {
    final connection = _connection;
    if (connection == null || connection.status != ConnectionStatus.pending) {
      return;
    }
    try {
      _connection = await _syncService.checkPairing(connection);
      _lastSyncError = null;
      notifyListeners();
      if (isConnected && unsynced.isNotEmpty) unawaited(syncPending());
      if (isConnected && _pendingBillCount > 0) unawaited(syncPendingBills());
    } on SyncFailure catch (error) {
      _connection = await _syncService.loadConnection();
      _lastSyncError = error.message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> forgetConnection() async {
    await _syncService.forgetConnection();
    _connection = null;
    _lastSyncError = null;
    notifyListeners();
  }

  Future<void> updateRecordRouting({
    required String deliveryScope,
    String? targetPosNodeId,
  }) async {
    final connection = _connection;
    if (connection == null) return;
    final selected = deliveryScope == 'selected' && targetPosNodeId != null;
    _connection = connection.copyWith(
      deliveryScope: selected ? 'selected' : 'all',
      targetPosNodeIds: selected ? [targetPosNodeId] : const [],
    );
    await _syncService.saveConnection(_connection!);
    notifyListeners();
  }

  Future<int> syncPending() async {
    if (_syncing || !isConnected) return 0;
    _syncing = true;
    _lastSyncError = null;
    notifyListeners();
    var count = 0;
    try {
      for (final action in unsynced.toList()) {
        final didSync = await _sync(action);
        if (!didSync) break;
        count++;
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
    return count;
  }

  Future<bool> syncOne(TallyAction action) async {
    if (!isConnected || action.synced) return false;
    _syncing = true;
    _lastSyncError = null;
    notifyListeners();
    try {
      return await _sync(action);
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<bool> _sync(TallyAction action) async {
    final connection = _connection;
    if (connection == null) return false;
    if (action.mediaAssets.isEmpty && action.hasMedia) {
      action.mediaAssets = _buildMediaAssets(
        action.voicePath,
        action.imagePaths,
      );
      await _repo.updateMediaAssets(action);
    }
    try {
      await _syncService.syncAction(
        action,
        connection,
        onMediaUpdated: _repo.updateMediaAssets,
      );
      if (action.id != null) await markSynced(action.id!);
      return true;
    } on SyncFailure catch (error) {
      _lastSyncError = error.message;
      return false;
    } on TimeoutException {
      _lastSyncError =
          'The server took too long to respond. Your entry is safe on this device.';
      return false;
    } on SocketException {
      _lastSyncError =
          'No connection to the sync server. Your entry is safe on this device.';
      return false;
    } catch (_) {
      _lastSyncError =
          'Could not sync right now. Your entry is safe on this device.';
      return false;
    }
  }

  Future<List<PosCatalogNode>> loadPosNodes({bool refresh = true}) async {
    var nodes = await _billingRepository.nodes();
    final connection = _connection;
    if (refresh && connection?.isConnected == true) {
      nodes = await _syncService.listPosNodes(connection!);
      await _billingRepository.replaceNodes(nodes);
    }
    return nodes;
  }

  Future<List<CatalogItem>> loadCatalog(
    String nodeId, {
    bool refresh = true,
  }) async {
    var items = await _billingRepository.catalog(nodeId);
    final connection = _connection;
    if (refresh && connection?.isConnected == true) {
      items = await _syncService.loadCatalog(connection!, nodeId);
      await _billingRepository.replaceCatalog(nodeId, items);
    }
    return items;
  }

  Future<bool> submitMobileBill(MobileBill bill) async {
    await _billingRepository.saveBill(bill);
    _pendingBillCount = await _billingRepository.pendingCount();
    _mobileBills.removeWhere(
      (saved) => saved.clientBillId == bill.clientBillId,
    );
    _mobileBills.insert(0, bill);
    notifyListeners();
    final connection = _connection;
    if (connection?.isConnected != true) return false;
    try {
      final id = await _syncService.submitMobileBillPayload(
        connection!,
        Map<String, dynamic>.from(bill.toApi()),
      );
      await _billingRepository.markBillSynced(bill.clientBillId, id);
      bill.synced = true;
      bill.serverId = id;
      bill.lastError = null;
      _pendingBillCount = await _billingRepository.pendingCount();
      notifyListeners();
      return true;
    } catch (error) {
      await _billingRepository.markBillError(
        bill.clientBillId,
        error.toString(),
      );
      bill.lastError = error.toString();
      _lastSyncError = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<int> syncPendingBills() async {
    final connection = _connection;
    if (connection?.isConnected != true || _syncingBills) return 0;
    _syncingBills = true;
    notifyListeners();
    var synced = 0;
    try {
      for (final payload in await _billingRepository.pendingBills()) {
        final clientId = '${payload['clientBillId']}';
        try {
          final id = await _syncService.submitMobileBillPayload(
            connection!,
            payload,
          );
          await _billingRepository.markBillSynced(clientId, id);
          synced++;
        } catch (error) {
          await _billingRepository.markBillError(clientId, error.toString());
          _lastSyncError = error.toString();
          break;
        }
      }
      _pendingBillCount = await _billingRepository.pendingCount();
      _mobileBills = await _billingRepository.bills();
      return synced;
    } finally {
      _syncingBills = false;
      notifyListeners();
    }
  }
}
