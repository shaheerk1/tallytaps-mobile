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

  List<TallyAction> get unsynced =>
      _actions.where((a) => a.isFinal && !a.synced).toList();

  /// Notes still being written. They stay on the phone, as many as there are.
  List<TallyAction> get drafts => _actions.where((a) => a.isDraft).toList();

  /// Finished notes, which are the ones the shop ever sees.
  List<TallyAction> get finalNotes => _actions.where((a) => a.isFinal).toList();

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

  /// Starts a new note. It is kept from the first word, like any notebook,
  /// and stays a draft until the person says it is finished.
  Future<TallyAction> startDraft() async {
    final action = TallyAction(
      type: ActionType.note,
      direction: ActionDirection.incoming,
      amount: 0,
      isDraft: true,
      createdAt: DateTime.now(),
    );
    action.id = await _repo.insert(action);
    _actions.insert(0, action);
    notifyListeners();
    return action;
  }

  /// Saves what has been written so far. An empty note is dropped instead of
  /// cluttering the list.
  Future<TallyAction?> saveDraft(TallyAction draft) async {
    if (draft.id == null) return null;
    if (!draft.hasContent) {
      await deleteNote(draft);
      return null;
    }
    await _repo.update(draft);
    final index = _actions.indexWhere((action) => action.id == draft.id);
    if (index >= 0) _actions[index] = draft;
    notifyListeners();
    return draft;
  }

  /// Marks a note finished: it stops being editable and joins the queue for
  /// the shop. What it is filed as follows what was attached to it.
  Future<TallyAction?> finalizeNote(TallyAction draft) async {
    if (draft.id == null || !draft.hasContent) return null;
    final finished = draft.copyWith(isDraft: false, type: _fileAs(draft));
    await _repo.update(finished);
    final index = _actions.indexWhere((action) => action.id == finished.id);
    if (index >= 0) _actions[index] = finished;
    _lastRecorded = finished;
    _lastRecordedNonce++;
    notifyListeners();
    if (isConnected) unawaited(syncPending());
    return finished;
  }

  /// A note is filed by what is on it, never by a category chosen up front.
  ActionType _fileAs(TallyAction note) {
    if (note.hasMoney) {
      return note.moneyMethod == 'card' ? ActionType.card : ActionType.cash;
    }
    return note.hasGoods ? ActionType.stock : ActionType.note;
  }

  /// Throws a note away. A finished one that already reached the shop stays
  /// there; this only clears it from the phone.
  Future<void> deleteNote(TallyAction note) async {
    if (note.id != null) await _repo.delete(note.id!);
    _actions.removeWhere((action) => action.id == note.id);
    notifyListeners();
  }

  /// One field note, as the person wrote it.
  ///
  /// They never pick a category: the note is filed by what they attached, so
  /// the shop's own lists and money totals keep working, and a plain note stays
  /// a plain note.
  Future<TallyAction> recordNote({
    required String note,
    double? amount,
    String moneyMethod = 'cash',
    ActionDirection moneyDirection = ActionDirection.incoming,
    String? item,
    String? productKey,
    double? handlingQty,
    String? handlingUom,
    double? baseQty,
    String? baseUom,
    String? who,
    List<String> tags = const [],
    bool needsDoing = false,
    String? voicePath,
    List<String> imagePaths = const [],
  }) async {
    final hasMoney = amount != null && amount > 0;
    final hasGoods = item != null && item.trim().isNotEmpty;
    final type = hasMoney
        ? (moneyMethod == 'card' ? ActionType.card : ActionType.cash)
        : hasGoods
        ? ActionType.stock
        : ActionType.note;
    final action = TallyAction(
      type: type,
      direction: moneyDirection,
      amount: hasMoney ? amount : 0,
      item: hasGoods ? item.trim() : null,
      qty: hasGoods ? handlingQty : null,
      unit: hasGoods ? handlingUom : null,
      note: note.trim().isEmpty ? null : note.trim(),
      who: (who == null || who.trim().isEmpty) ? null : who.trim(),
      tags: tags,
      needsDoing: needsDoing,
      productKey: productKey,
      baseQty: hasGoods ? baseQty : null,
      baseUnit: hasGoods ? baseUom : null,
      moneyMethod: hasMoney ? moneyMethod : null,
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
    unawaited(refreshFollowUps());
    return count;
  }

  /// Asks the host which notes have been seen to, so one that was waiting can
  /// stop waiting. Quiet about failure: it is news, not the record itself.
  Future<void> refreshFollowUps() async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return;
    final waiting = _actions.where((action) => action.isWaiting && action.id != null).toList();
    if (waiting.isEmpty) return;
    try {
      final rows = await _syncService.listFollowUps(connection);
      if (rows.isEmpty) return;
      final byId = <String, Map<String, String?>>{
        for (final row in rows) row['clientRecordId']!: row,
      };
      var changed = false;
      for (final action in waiting) {
        final row = byId['${connection.deviceId}-${action.id}'];
        if (row == null) continue;
        final resolvedAt = DateTime.tryParse(row['resolvedAt'] ?? '')?.toLocal();
        if (resolvedAt == null) continue;
        await _repo.markResolved(action.id!, resolvedAt, row['resolvedBy']);
        final index = _actions.indexWhere((candidate) => candidate.id == action.id);
        if (index >= 0) _actions[index] = _actions[index].seenAtShop(resolvedAt, row['resolvedBy']);
        changed = true;
      }
      if (changed) notifyListeners();
    } on SyncFailure {
      // Offline, or an older host: the note simply keeps waiting.
    } on MonitorAccessRevoked {
      // Not related to notes; nothing to do here.
    }
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

  /// Every item this phone knows from the shops it is connected to, for naming
  /// goods on a note. Read from what is already downloaded so it works offline.
  Future<List<CatalogItem>> loadCatalogItems() async {
    final nodes = await _billingRepository.nodes();
    final items = <CatalogItem>[];
    final seen = <String>{};
    for (final node in nodes) {
      for (final item in await _billingRepository.catalog(node.id)) {
        if (seen.add('${node.id}|${item.sourceProductKey}')) items.add(item);
      }
    }
    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return items;
  }

  /// Names already used on notes, newest first, so the same person is written
  /// the same way next time.
  List<String> get rememberedWho {
    final names = <String>[];
    for (final action in _actions) {
      final who = action.who?.trim();
      if (who != null && who.isNotEmpty && !names.contains(who)) names.add(who);
      if (names.length >= 20) break;
    }
    return names;
  }

  /// Tags already used, most used first.
  List<String> get rememberedTags {
    final counts = <String, int>{};
    for (final action in _actions) {
      for (final tag in action.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final tags = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return tags.take(24).toList();
  }

  /// Notes still waiting on somebody at the shop.
  List<TallyAction> get waitingNotes =>
      _actions.where((action) => action.isWaiting).toList();

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
