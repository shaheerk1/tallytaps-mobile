import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentity {
  const DeviceIdentity({
    required this.id,
    required this.platform,
    required this.name,
    required this.model,
    required this.appVersion,
  });

  final String id;
  final String platform;
  final String name;
  final String model;
  final String appVersion;

  Map<String, Object?> toPairingMap() => {
    'deviceId': id,
    'platform': platform,
    'name': name,
    'model': model,
    'appVersion': appVersion,
  };
}

class DeviceIdentityService {
  DeviceIdentityService({
    FlutterSecureStorage? storage,
    DeviceInfoPlugin? deviceInfo,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  static const _idKey = 'tally_device_id_v1';
  final FlutterSecureStorage _storage;
  final DeviceInfoPlugin _deviceInfo;

  Future<DeviceIdentity> getIdentity() async {
    var id = await _storage.read(key: _idKey);
    id ??= const Uuid().v4();
    await _storage.write(key: _idKey, value: id);

    final package = await PackageInfo.fromPlatform();
    final appVersion = '${package.version}+${package.buildNumber}';
    if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      return DeviceIdentity(
        id: id,
        platform: 'android',
        name: info.device.isEmpty ? info.model : info.device,
        model: info.model,
        appVersion: appVersion,
      );
    }
    if (Platform.isIOS) {
      final info = await _deviceInfo.iosInfo;
      return DeviceIdentity(
        id: id,
        platform: 'ios',
        name: info.name,
        model: info.model,
        appVersion: appVersion,
      );
    }
    return DeviceIdentity(
      id: id,
      platform: Platform.operatingSystem,
      name: Platform.localHostname,
      model: Platform.operatingSystemVersion,
      appVersion: appVersion,
    );
  }
}
