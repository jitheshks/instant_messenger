// controller/contacts_screen_controller.dart
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

class ContactsScreenController extends ChangeNotifier {
  final TextEditingController searchText = TextEditingController();
  bool _searching = false;
  String _query = '';

  bool get searching => _searching;
  String get query => _query;

  // NEW: last debug-fetched result (simple map: {'name':..., 'phone':...})
  List<Map<String, String>> lastDebugFetchedContacts = [];

  void startSearch() {
    if (_searching) return;
    _searching = true;
    notifyListeners();
  }

  void stopSearch() {
    if (!_searching) return;
    _searching = false;
    _query = '';
    searchText.clear();
    notifyListeners();
  }

  void onQueryChanged(String v) {
    _query = v.trim();
    notifyListeners();
  }

  Future<void> refresh() async {
    // Optional: if repository supports a manual refresh trigger, call it here.
    // For now, just provide a hook and maybe show a SnackBar in UI.
  }

  Future<void> inviteFriend() async {
    // TODO: share invite link/text through Share API if desired.
  }

  /// Opens the system contacts app (best-effort).
  Future<void> openSystemContacts() async {
    // This is a simple helper: it just attempts to launch the platform contact picker.
    // You can replace with a more robust platform-channel based opener if desired.
    try {
      // flutter_contacts does not open the system UI for editing; this is a placeholder.
      debugPrint('[ContactsController] openSystemContacts called (no-op placeholder)');
    } catch (e, st) {
      debugPrint('[ContactsController] openSystemContacts error: $e\n$st');
    }
  }

  /// Request contacts permission (uses permission_handler).
  /// Returns true if permission is granted.
  Future<bool> requestContactsPermission() async {
    try {
      final status = await Permission.contacts.status;
      debugPrint('[ContactsController] Permission.contacts.status -> $status');

      if (!status.isGranted) {
        final req = await Permission.contacts.request();
        debugPrint('[ContactsController] Permission.contacts.request -> $req');
        if (req.isPermanentlyDenied) {
          debugPrint('[ContactsController] contacts permanently denied; consider opening app settings');
        }
      }

      final after = await Permission.contacts.status;
      debugPrint('[ContactsController] Permission.contacts.status (after) -> $after');
      return after.isGranted;
    } catch (e, st) {
      debugPrint('[ContactsController] requestContactsPermission error: $e\n$st');
      return false;
    }
  }

  /// Fetch a small set of device contacts using flutter_contacts.
  /// Returns a list of maps with keys: 'displayName' and 'phone' (first phone found).
  /// This method does its own permission check (best-effort).
  Future<List<Map<String, String>>> fetchDeviceContacts({int limit = 50}) async {
    try {
      // Ensure runtime permission
      final ok = await requestContactsPermission();
      if (!ok) {
        debugPrint('[ContactsController] fetchDeviceContacts aborted — permission not granted');
        return <Map<String, String>>[];
      }

      // flutter_contacts also requires explicit permission call (some devices)
      final fcPerm = await FlutterContacts.requestPermission(readonly: true);
      debugPrint('[ContactsController] FlutterContacts.requestPermission -> $fcPerm');
      if (!fcPerm) {
        debugPrint('[ContactsController] flutter_contacts permission denied');
        return <Map<String, String>>[];
      }

      final list = await FlutterContacts.getContacts(withProperties: true);
      debugPrint('[ContactsController] flutter_contacts returned ${list.length} contacts');

      final results = <Map<String, String>>[];
      var count = 0;
      for (final c in list) {
        final name = c.displayName ;
        final phone = (c.phones.isNotEmpty) ? (c.phones.first.number ) : '';
        results.add({'displayName': name, 'phone': phone});
        count++;
        if (count >= limit) break;
      }

      // store last fetched for UI/tests
      lastDebugFetchedContacts = results;
      debugPrint('[ContactsController] fetchDeviceContacts -> returning ${results.length} entries');
      return results;
    } catch (e, st) {
      debugPrint('[ContactsController] fetchDeviceContacts error: $e\n$st');
      return <Map<String, String>>[];
    }
  }

  /// Convenience: run fetchDeviceContacts() and then notify listeners.
  /// Useful if the UI relies on controller.lastDebugFetchedContacts.
  Future<void> triggerDebugFetchAndNotify({int limit = 50}) async {
    lastDebugFetchedContacts = await fetchDeviceContacts(limit: limit);
    notifyListeners();
  }

  @override
  void dispose() {
    searchText.dispose();
    super.dispose();
  }
}
