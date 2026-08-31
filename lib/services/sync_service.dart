import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/media_attachment.dart';
import '../models/tally_action.dart';
import '../models/mobile_bill.dart';
import 'device_identity_service.dart';
import 'sync_config_service.dart';
import 'sync_diagnostics_service.dart';

class SyncFailure implements Exception {
  const SyncFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class SyncService {
  SyncService({
    SyncConfigService? config,
    DeviceIdentityService? identity,
    SyncDiagnosticsService? diagnostics,
    http.Client? client,
  }) : _config = config ?? SyncConfigService(),
       _identity = identity ?? DeviceIdentityService(),
       _diagnostics = diagnostics ?? SyncDiagnosticsService(),
       _client = client ?? http.Client();

  final SyncConfigService _config;
  final DeviceIdentityService _identity;
  final SyncDiagnosticsService _diagnostics;
  final http.Client _client;

  Future<SyncConnection?> loadConnection() => _config.load();

  Future<SyncConnection> requestPairing({
    required String serverUrl,
    required String hostCode,
  }) async {
    final uri = _apiUri(serverUrl, '/api/v1/pairing/requests');
    final identity = await _identity.getIdentity();
    final response = await _client
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'hostCode': hostCode.trim().toUpperCase(),
            'device': identity.toPairingMap(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncFailure(
        _message(body, fallback: 'Could not request connection.'),
      );
    }
    final requestId = body['requestId'] as String?;
    final requestSecret = body['requestSecret'] as String?;
    if (requestId == null || requestSecret == null) {
      throw const SyncFailure(
        'The server returned an incomplete pairing request.',
      );
    }
    final connection = SyncConnection(
      serverUrl: _normaliseServerUrl(serverUrl),
      hostCode: hostCode.trim().toUpperCase(),
      deviceId: identity.id,
      status: ConnectionStatus.pending,
      requestId: requestId,
      requestSecret: requestSecret,
    );
    await _config.save(connection);
    return connection;
  }

  Future<SyncConnection> checkPairing(SyncConnection connection) async {
    final requestId = connection.requestId;
    final secret = connection.requestSecret;
    if (requestId == null || secret == null) {
      throw const SyncFailure(
        'This connection request is incomplete. Start it again.',
      );
    }
    final response = await _client
        .get(
          _apiUri(connection.serverUrl, '/api/v1/pairing/requests/$requestId'),
          headers: {'X-Pairing-Secret': secret},
        )
        .timeout(const Duration(seconds: 15));
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncFailure(
        _message(body, fallback: 'Could not check connection approval.'),
      );
    }
    final status = body['status'] as String?;
    if (status == 'approved') {
      final token = body['deviceToken'] as String?;
      if (token == null || token.isEmpty) {
        throw const SyncFailure(
          'The server approved this device without a device token.',
        );
      }
      final connected = connection.copyWith(
        status: ConnectionStatus.connected,
        deviceToken: token,
      );
      await _config.save(connected);
      return connected;
    }
    if (status == 'rejected' || status == 'revoked') {
      await _config.clear();
      throw const SyncFailure('This connection request was not approved.');
    }
    return connection;
  }

  Future<void> forgetConnection() => _config.clear();

  Future<void> saveConnection(SyncConnection connection) => _config.save(connection);

  Future<List<PosCatalogNode>> listPosNodes(SyncConnection connection) async {
    final body = await _deviceGet(connection, '/api/v1/mobile/pos-nodes');
    final nodes = body['nodes'];
    if (nodes is! List) {
      throw const SyncFailure('The server returned an invalid POS list.');
    }
    return nodes
        .whereType<Map>()
        .map((node) => PosCatalogNode.fromMap(Map<String, dynamic>.from(node)))
        .toList();
  }

  Future<List<CatalogItem>> loadCatalog(
    SyncConnection connection,
    String nodeId,
  ) async {
    final body = await _deviceGet(
      connection,
      '/api/v1/mobile/catalogs/${Uri.encodeComponent(nodeId)}',
    );
    final items = body['items'];
    if (items is! List) {
      throw const SyncFailure('The server returned an invalid item catalog.');
    }
    return items
        .whereType<Map>()
        .map(
          (item) =>
              CatalogItem.fromApi(nodeId, Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<String> submitMobileBillPayload(
    SyncConnection connection,
    Map<String, dynamic> payload,
  ) async {
    final token = connection.deviceToken;
    if (!connection.isConnected || token == null) {
      throw const SyncFailure('Connect this device before sending a bill.');
    }
    final response = await _client
        .post(
          _apiUri(connection.serverUrl, '/api/v1/mobile/bills'),
          headers: {
            'Content-Type': 'application/json',
            HttpHeaders.authorizationHeader: 'Bearer $token',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncFailure(_message(body, fallback: 'Could not send this bill.'));
    }
    final id = body['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const SyncFailure('The server did not return a bill ID.');
    }
    return id;
  }

  Future<Map<String, dynamic>> _deviceGet(
    SyncConnection connection,
    String path,
  ) async {
    final token = connection.deviceToken;
    if (!connection.isConnected || token == null) {
      throw const SyncFailure('Connect this device before loading POS data.');
    }
    final response = await _client
        .get(
          _apiUri(connection.serverUrl, path),
          headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncFailure(_message(body, fallback: 'Could not load POS data.'));
    }
    return body;
  }

  /// Sends needed attachments first, then the action. A callback persists an
  /// uploaded server ID immediately, so a later failure only retries what is left.
  Future<void> syncAction(
    TallyAction action,
    SyncConnection connection, {
    required Future<void> Function(TallyAction action) onMediaUpdated,
  }) async {
    final token = connection.deviceToken;
    if (!connection.isConnected || token == null) {
      throw const SyncFailure('Connect this device before syncing.');
    }
    await _diagnostics.log(
      'Sync started for local record ${action.id ?? 'unsaved'} with ${action.mediaAssets.length} attachment(s).',
    );
    try {
      for (var index = 0; index < action.mediaAssets.length; index++) {
        final asset = action.mediaAssets[index];
        if (asset.uploaded) {
          await _diagnostics.log(
            'Attachment ${index + 1}/${action.mediaAssets.length} was already uploaded.',
          );
          continue;
        }
        final uploaded = await _uploadMedia(asset, connection.serverUrl, token);
        action.mediaAssets[index] = asset.copyWith(remoteId: uploaded);
        await onMediaUpdated(action);
      }
      final response = await _client
          .post(
            _apiUri(connection.serverUrl, '/api/v1/records'),
            headers: {
              'Content-Type': 'application/json',
              HttpHeaders.authorizationHeader: 'Bearer $token',
            },
            body: jsonEncode({
              'clientRecordId': action.id == null
                  ? 'local-${action.createdAt.microsecondsSinceEpoch}'
                  : '${connection.deviceId}-${action.id}',
              'type': action.type.name,
              'direction': action.direction.name,
              'amount': action.amount,
              'item': action.item,
              'qty': action.qty,
              'unit': action.unit,
              'note': action.note,
              'createdAt': action.createdAt.toUtc().toIso8601String(),
              'mediaIds': action.mediaAssets
                  .where((asset) => asset.uploaded)
                  .map((asset) => asset.remoteId)
                  .toList(),
              'deliveryScope': connection.deliveryScope,
              'targetPosNodeIds': connection.deliveryScope == 'selected'
                  ? connection.targetPosNodeIds
                  : const <String>[],
            }),
          )
          .timeout(const Duration(seconds: 20));
      final body = _decode(response);
      await _diagnostics.log(
        'Record sync response: HTTP ${response.statusCode}.',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncFailure(
          _message(body, fallback: 'Could not sync this entry.'),
        );
      }
      await _diagnostics.log('Sync completed successfully.');
    } catch (error) {
      await _diagnostics.log(
        'Sync failed: ${SyncDiagnosticsService.errorSummary(error)}',
      );
      rethrow;
    }
  }

  Future<String> _uploadMedia(
    MediaAttachment asset,
    String serverUrl,
    String token,
  ) async {
    final file = File(asset.localPath);
    if (!await file.exists()) {
      await _diagnostics.log(
        'Attachment upload skipped: the ${asset.type.name} file is missing.',
      );
      throw SyncFailure(
        'An attached ${asset.type.name} file is no longer on this device.',
      );
    }
    final bytes = await file.length();
    await _diagnostics.log(
      'Attachment upload started: ${asset.type.name}, $bytes bytes.',
    );
    try {
      final request =
          http.MultipartRequest('POST', _apiUri(serverUrl, '/api/v1/media'))
            ..headers[HttpHeaders.authorizationHeader] = 'Bearer $token'
            ..fields['clientMediaId'] = asset.clientMediaId
            ..files.add(
              await http.MultipartFile.fromPath('file', asset.localPath),
            );
      final response = await request.send().timeout(
        const Duration(seconds: 45),
      );
      final decoded = _decodeText(await response.stream.bytesToString());
      await _diagnostics.log(
        'Attachment upload response: HTTP ${response.statusCode}.',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncFailure(
          _message(decoded, fallback: 'Could not upload attachment.'),
        );
      }
      final rawAsset = decoded['asset'];
      final id =
          decoded['id'] as String? ??
          (rawAsset is Map ? rawAsset['id'] as String? : null);
      if (id == null || id.isEmpty) {
        throw const SyncFailure('The server did not return an attachment ID.');
      }
      await _diagnostics.log('Attachment upload completed successfully.');
      return id;
    } catch (error) {
      await _diagnostics.log(
        'Attachment upload failed: ${SyncDiagnosticsService.errorSummary(error)}',
      );
      rethrow;
    }
  }

  static Uri _apiUri(String serverUrl, String path) =>
      Uri.parse('${_normaliseServerUrl(serverUrl)}$path');

  static String _normaliseServerUrl(String value) {
    final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) throw const SyncFailure('Enter your server address.');
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        uri.host.isEmpty ||
        !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw const SyncFailure(
        'Enter a valid server address, such as https://sync.example.com.',
      );
    }
    if (kReleaseMode && uri.scheme != 'https') {
      throw const SyncFailure(
        'For security, the production app can only connect to an HTTPS server.',
      );
    }
    return uri.toString().replaceFirst(RegExp(r'/$'), '');
  }

  static Map<String, dynamic> _decode(http.Response response) =>
      _decodeText(response.body);

  static Map<String, dynamic> _decodeText(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } on FormatException {
      return {};
    }
  }

  static String _message(
    Map<String, dynamic> body, {
    required String fallback,
  }) => body['message'] as String? ?? body['error'] as String? ?? fallback;
}
