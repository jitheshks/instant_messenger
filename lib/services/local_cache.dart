// lib/services/local_cache.dart
import 'package:hive/hive.dart';

class LocalCache {
  static Box get _profile => Hive.box('profile');
  static Box get _contacts => Hive.box('contacts');
  static Box get _chatsMeta => Hive.box('chats_meta');

  
// Profile cache getters (MATCH FIRESTORE KEYS)
static String? get displayName => _profile.get('display_name');
static String? get bio => _profile.get('bio');
static String? get avatarUrl => _profile.get('avatar_url');
static String? get phoneE164 => _profile.get('phone_e164');


  // Profile cache setter (with phoneE164)
static Future<void> setProfile({
  String? displayName,
  String? bio,
  String? avatarUrl,
  String? phoneE164,
}) async {
  if (displayName != null) {
    await _profile.put('display_name', displayName);
  }
  if (bio != null) {
    await _profile.put('bio', bio);
  }
  if (avatarUrl != null) {
    await _profile.put('avatar_url', avatarUrl);
  }
  if (phoneE164 != null) {
    await _profile.put('phone_e164', phoneE164);
  }
}

  // Contacts cache
  static Map<String, dynamic>? getContact(String uid) {
    final m = _contacts.get(uid);
    return (m is Map) ? Map<String, dynamic>.from(m) : null;
  }

  static Future<void> setContact(String uid, Map<String, dynamic> data) async {
    await _contacts.put(uid, data);
  }

  // Chat metadata cache
  static Map<String, dynamic>? getChatMeta(String chatId) {
    final m = _chatsMeta.get(chatId);
    return (m is Map) ? Map<String, dynamic>.from(m) : null;
  }

  static Future<void> setChatMeta(
    String chatId,
    Map<String, dynamic> data,
  ) async {
    await _chatsMeta.put(chatId, data);
  }
}
