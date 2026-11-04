import 'package:package_info_plus/package_info_plus.dart';

/// AppInfoService provides cached access to application package metadata.
/// Ensure WidgetsFlutterBinding.ensureInitialized() has run before using.
class AppInfoService {
  PackageInfo? _cached;

  Future<PackageInfo> get info async {
    if (_cached != null) return _cached!;
    _cached = await PackageInfo.fromPlatform();
    return _cached!;
  }

  Future<String> appName() async => (await info).appName;
  Future<String> packageName() async => (await info).packageName;
  Future<String> version() async => (await info).version;
  Future<String> buildNumber() async => (await info).buildNumber;
  Future<String> buildSignature() async => (await info).buildSignature;
  Future<String?> installerStore() async => (await info).installerStore;
  Future<DateTime?> installTime() async => (await info).installTime;
  Future<DateTime?> updateTime() async => (await info).updateTime;

  Future<String> versionPlusBuild() async {
    final p = await info;
    return '${p.version}+${p.buildNumber}';
  }

  Future<Map<String, dynamic>> asMap() async => (await info).data;

  void setMock(PackageInfo mock) {
    _cached = mock;
  }
}
