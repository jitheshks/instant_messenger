// lib/services/acess_service_contact.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:instant_messenger/services/permission_service.dart';

class DeviceContact {
  final String savedName;
  final String phoneRaw;
  final String? phoneE164;

  DeviceContact({required this.savedName, required this.phoneRaw, this.phoneE164});
}

class ContactsAccessService {
  Future<List<DeviceContact>> readPhoneContacts() async {
    try {
      // 1) Permission via permission_handler
      final ok = await PermissionService.ensureContacts();
      if (!ok) {
        // 2) Fallback to FlutterContacts
        final fcOk = await FlutterContacts.requestPermission(readonly: true);
        if (!fcOk) {
          debugPrint('[ContactsAccess] permission denied');
          return const <DeviceContact>[];
        }
      }

      final contacts = await FlutterContacts.getContacts(withProperties: true);
      debugPrint('[ContactsAccess] total contacts: ${contacts.length}');
      for (final c in contacts.take(5)) {
        debugPrint('[ContactsAccess] name=${c.displayName} phones=${c.phones.map((p) => p.number).toList()}');
      }

      final result = <DeviceContact>[];
      for (final c in contacts) {
        for (final p in c.phones) {
          final raw = p.number.replaceAll(RegExp(r'[^\d+]'), '');
          if (raw.isEmpty) continue;
          result.add(DeviceContact(savedName: c.displayName, phoneRaw: raw));
        }
      }
      debugPrint('[ContactsAccess] flattened entries: ${result.length}');
      for (final r in result.take(5)) {
        debugPrint('[ContactsAccess] savedName=${r.savedName} phoneRaw=${r.phoneRaw}');
      }

      return result;
    } catch (e, st) {
      debugPrint('[ContactsAccess] error: $e');
      debugPrintStack(stackTrace: st);
      return const <DeviceContact>[];
    }
  }
}
