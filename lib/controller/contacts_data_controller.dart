import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'package:instant_messenger/models/contact_list_entry.dart';
import 'package:instant_messenger/services/contact_repository.dart';

class ContactsDataController extends ChangeNotifier {
  ContactsDataController(this._repo);

  final ContactsRepository _repo;

  // Cached matched contacts (device ∩ registered users)
  List<ContactListEntry> cachedMatched = [];

  StreamSubscription<List<ContactListEntry>>? _sub;
  bool _loading = false;

  // --------------------------------------------------
  // PUBLIC STREAMS (used by UI if needed)
  // --------------------------------------------------

  Stream<List<ContactListEntry>> watchDirectory({int limit = 1000}) =>
      _repo.watchDirectory(limit: limit);

  Stream<List<ContactListEntry>> watchMatched({String defaultIso2 = 'IN'}) =>
      _repo.watchMatched(defaultIso2: defaultIso2);

  // --------------------------------------------------
  // CORE LOGIC
  // --------------------------------------------------

  /// Initial load OR normal reload
  Future<void> loadMatchedContacts({bool force = false}) async {
    if (_loading) return;
    if (!force && cachedMatched.isNotEmpty) return;

    final granted = await Permission.contacts.isGranted;
    if (!granted) {
      debugPrint('[ContactsData] load skipped → permission denied');
      return;
    }

    debugPrint('[ContactsData] loading matched contacts...');
    _loading = true;
    notifyListeners();

    await _sub?.cancel();
    _sub = _repo.watchMatched().listen(
      (entries) {
        cachedMatched = entries;
        _loading = false;
        notifyListeners();
        debugPrint(
          '[ContactsData] matched contacts updated: ${entries.length}',
        );
      },
      onError: (e, st) {
        debugPrint('[ContactsData] stream error: $e');
        debugPrintStack(stackTrace: st);
        _loading = false;
        notifyListeners();
      },
    );
  }

  /// 🔄 Call this AFTER permission is granted (first launch / settings)
  Future<void> refreshIfPermitted() async {
    final granted = await Permission.contacts.isGranted;

    if (!granted) {
      debugPrint('[ContactsData] refresh skipped → permission denied');
      return;
    }

    debugPrint('[ContactsData] refreshing after permission grant');
    await loadMatchedContacts(force: true);
  }

  // --------------------------------------------------
  // DEBUG / DEV HELPERS (SAFE TO KEEP)
  // --------------------------------------------------

  /// Debug helper – checks permission & fetches raw device contacts
  Future<void> debugContactsPermissionAndFetch() async {
    try {
      final st = await Permission.contacts.status;
      debugPrint('[DEBUG] Permission.contacts.status -> $st');

      if (!st.isGranted) {
        final req = await Permission.contacts.request();
        debugPrint('[DEBUG] Permission.contacts.request -> $req');
      }

      final after = await Permission.contacts.status;
      debugPrint('[DEBUG] Permission.contacts.status (after) -> $after');

      if (!after.isGranted) {
        debugPrint('[DEBUG] contacts permission still NOT granted.');
        return;
      }

      final fcPerm =
          await FlutterContacts.requestPermission(readonly: true);
      debugPrint('[DEBUG] FlutterContacts.requestPermission -> $fcPerm');

      if (!fcPerm) {
        debugPrint('[DEBUG] flutter_contacts permission rejected.');
        return;
      }

      final contacts =
          await FlutterContacts.getContacts(withProperties: true);

      debugPrint(
        '[DEBUG] flutter_contacts fetched ${contacts.length} contacts',
      );

      for (var c in contacts.take(5)) {
        final phones =
            c.phones.map((p) => p.number).join(', ');
        debugPrint(
          '[DEBUG] contact: "${c.displayName}" phones="$phones"',
        );
      }
    } catch (e, st) {
      debugPrint('[DEBUG] fetch error: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  // --------------------------------------------------
  // CLEANUP
  // --------------------------------------------------

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
