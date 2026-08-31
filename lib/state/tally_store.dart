import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/action_repository.dart';
import '../models/media_attachment.dart';
import '../models/tally_action.dart';
import '../services/sync_config_service.dart';
import '../services/sync_service.dart';

/// App-wide state. Holds every recorded action in memory after each change
/// so the UI always reflects what is on disk.
class TallyStore extends ChangeNotifier {
  TallyStore(this._repo, {SyncService? syncService})
    : _syncService = syncService ?? SyncService();

  final ActionRepository _repo;
  final SyncService _syncService;

  List<TallyAction> _actions = [];
  bool _loading = true;
  TallyAction? _lastRecorded;
  int _lastRecordedNonce = 0;
  SyncConnection? _connection;
  bool _syncing = false;
  String? _lastSyncError;

  List<TallyAction> get actions => _actions;
  bool get loading => _loading;
  SyncConnection? get connection => _connection;
  bool get syncing => _syncing;
  String? get lastSyncError => _lastSyncError;
  bool get isConnected => _connection?.isConnected ?? false;

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
    _loading = false;
    notifyListeners();
    if (isConnected && unsynced.isNotEmpty) {
      unawaited(syncPending());
    }
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
    if (connection == null || connection.status != ConnectionStatus.pending) return;
    try {
      _connection = await _syncService.checkPairing(connection);
      _lastSyncError = null;
      notifyListeners();
      if (isConnected && unsynced.isNotEmpty) unawaited(syncPending());
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
      action.mediaAssets = _buildMediaAssets(action.voicePath, action.imagePaths);
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
      _lastSyncError = 'The server took too long to respond. Your entry is safe on this device.';
      return false;
    } on SocketException {
      _lastSyncError = 'No connection to the sync server. Your entry is safe on this device.';
      return false;
    } catch (_) {
      _lastSyncError = 'Could not sync right now. Your entry is safe on this device.';
      return false;
    }
  }
}
