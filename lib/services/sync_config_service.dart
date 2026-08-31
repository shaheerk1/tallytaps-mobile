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
  });

  final String serverUrl;
  final String hostCode;
  final String deviceId;
  final ConnectionStatus status;
  final String? deviceToken;
  final String? requestId;
  final String? requestSecret;

  bool get isConnected => status == ConnectionStatus.connected && deviceToken != null;

  SyncConnection copyWith({
    ConnectionStatus? status,
    String? deviceToken,
    String? requestId,
    String? requestSecret,
  }) => SyncConnection(
    serverUrl: serverUrl,
    hostCode: hostCode,
    deviceId: deviceId,
    status: status ?? this.status,
    deviceToken: deviceToken ?? this.deviceToken,
    requestId: requestId ?? this.requestId,
    requestSecret: requestSecret ?? this.requestSecret,
  );

  Map<String, Object?> toMap() => {
    'serverUrl': serverUrl,
    'hostCode': hostCode,
    'deviceId': deviceId,
    'status': status.name,
    'deviceToken': deviceToken,
    'requestId': requestId,
    'requestSecret': requestSecret,
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
