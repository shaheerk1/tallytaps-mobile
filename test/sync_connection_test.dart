import 'package:flutter_test/flutter_test.dart';
import 'package:tally/services/sync_config_service.dart';

void main() {
  test('old connections default quick records to every POS', () {
    final connection = SyncConnection.fromMap({
      'serverUrl': 'https://example.test',
      'hostCode': 'TH-TEST',
      'deviceId': 'phone-1',
      'status': 'connected',
      'deviceToken': 'token',
    });
    expect(connection.deliveryScope, 'all');
    expect(connection.targetPosNodeIds, isEmpty);
  });

  test('selected quick-record destination survives secure serialization', () {
    const connection = SyncConnection(
      serverUrl: 'https://example.test',
      hostCode: 'TH-TEST',
      deviceId: 'phone-1',
      status: ConnectionStatus.connected,
      deviceToken: 'token',
      deliveryScope: 'selected',
      targetPosNodeIds: ['node-1'],
    );
    final restored = SyncConnection.fromMap(connection.toMap());
    expect(restored.deliveryScope, 'selected');
    expect(restored.targetPosNodeIds, ['node-1']);
  });
}
