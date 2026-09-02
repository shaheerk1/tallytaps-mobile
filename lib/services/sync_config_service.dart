import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum ConnectionStatus { disconnected, pending, connected }

class SyncConnection {
  const SyncConnection({
    required this.serverUrl,
    required this.hostCode,
    required this.deviceId,
    required this.status,
    this.deviceToken,
    this.requestId,
    this.requestSecret,
    this.deliveryScope = 'all',
    this.targetPosNodeIds = const [],
    this.monitorAccess = false,
  });

  final String serverUrl;
  final String hostCode;
  final String deviceId;
  final ConnectionStatus status;
  final String? deviceToken;
  final String? requestId;
  final String? requestSecret;
  final String deliveryScope;
  final List<String> targetPosNodeIds;

  /// Whether the host has granted this device Business Monitor access.
  ///
  /// The server decides this and re-checks it on every monitor request; the
  /// stored copy only decides whether the entry point is drawn before the first
  /// call comes back. It is never trusted as authorization.
  final bool monitorAccess;

  bool get isConnected => status == ConnectionStatus.connected && deviceToken != null;

  SyncConnection copyWith({
    ConnectionStatus? status,
    String? deviceToken,
    String? requestId,
    String? requestSecret,
    String? deliveryScope,
    List<String>? targetPosNodeIds,
  }) => SyncConnection(
    serverUrl: serverUrl,
    hostCode: hostCode,
    deviceId: deviceId,
    status: status ?? this.status,
    deviceToken: deviceToken ?? this.deviceToken,
    requestId: requestId ?? this.requestId,
    requestSecret: requestSecret ?? this.requestSecret,
    deliveryScope: deliveryScope ?? this.deliveryScope,
    targetPosNodeIds: targetPosNodeIds ?? this.targetPosNodeIds,
    monitorAccess: monitorAccess,
  );

  /// Kept separate from [copyWith] so the grant can be cleared, not just set.
  SyncConnection withMonitorAccess(bool granted) => SyncConnection(
    serverUrl: serverUrl,
    hostCode: hostCode,
    deviceId: deviceId,
    status: status,
    deviceToken: deviceToken,
    requestId: requestId,
    requestSecret: requestSecret,
    deliveryScope: deliveryScope,
    targetPosNodeIds: targetPosNodeIds,
    monitorAccess: granted,
  );

  Map<String, Object?> toMap() => {
    'serverUrl': serverUrl,
    'hostCode': hostCode,
    'deviceId': deviceId,
    'status': status.name,
    'deviceToken': deviceToken,
    'requestId': requestId,
    'requestSecret': requestSecret,
    'deliveryScope': deliveryScope,
    'targetPosNodeIds': targetPosNodeIds,
    'monitorAccess': monitorAccess,
  };

  factory SyncConnection.fromMap(Map<String, Object?> map) => SyncConnection(
    serverUrl: map['serverUrl'] as String? ?? '',
    hostCode: map['hostCode'] as String? ?? '',
    deviceId: map['deviceId'] as String? ?? '',
    status: ConnectionStatus.values.firstWhere(
      (value) => value.name == map['status'],
      orElse: () => ConnectionStatus.disconnected,
    ),
    deviceToken: map['deviceToken'] as String?,
    requestId: map['requestId'] as String?,
    requestSecret: map['requestSecret'] as String?,
    deliveryScope: map['deliveryScope'] == 'selected' ? 'selected' : 'all',
    targetPosNodeIds: (map['targetPosNodeIds'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const [],
    monitorAccess: map['monitorAccess'] == true,
  );
}

/// Keeps the device token and pairing secret out of SQLite and plain settings.
class SyncConfigService {
  SyncConfigService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _connectionKey = 'sync_connection_v1';
  final FlutterSecureStorage _storage;

  Future<SyncConnection?> load() async {
    final raw = await _storage.read(key: _connectionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return null;
      final connection = SyncConnection.fromMap(Map<String, Object?>.from(value));
      return connection.serverUrl.isEmpty || connection.hostCode.isEmpty
          ? null
          : connection;
    } on FormatException {
      return null;
    }
  }

  Future<void> save(SyncConnection connection) => _storage.write(
    key: _connectionKey,
    value: jsonEncode(connection.toMap()),
  );

  Future<void> clear() => _storage.delete(key: _connectionKey);
}
