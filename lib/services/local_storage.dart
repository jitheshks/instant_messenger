import 'package:shared_preferences/shared_preferences.dart';
class LocalStorage {
  // 🔥 renamed for clarity (this is NOT user onboarding)
  static const _kPermissionsAsked = 'permissions_asked';
  static const _kLastPhone = 'last_phone_e164';

  Future<void> setPermissionsAsked(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPermissionsAsked, v);
  }

  Future<bool> getPermissionsAsked() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kPermissionsAsked) ?? false;
  }

  Future<void> saveLastPhone(String e164) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastPhone, e164);
  }

  Future<String?> getLastPhone() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLastPhone);
  }
}
