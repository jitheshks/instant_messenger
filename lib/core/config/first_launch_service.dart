import 'package:shared_preferences/shared_preferences.dart';

class FirstLaunchService {
  static const _key = 'first_launch_permissions_done';

  static Future<bool> isDone() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_key) ?? false;
  }

  static Future<void> markDone() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_key, true);
  }
}
