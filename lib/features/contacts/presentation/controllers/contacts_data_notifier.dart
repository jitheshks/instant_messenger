import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:instant_messenger/features/contacts/data/contact_repository.dart';
import 'package:instant_messenger/features/contacts/presentation/providers/contacts_providers.dart';
import 'package:instant_messenger/features/contacts/domain/models/contact_list_entry.dart';

@immutable
class ContactsDataState {
  final List<ContactListEntry> cachedMatched;
  final bool loading;
  final String? errorMessage;
  final bool isRateLimited;
  final DateTime? lastSyncedAt;

  const ContactsDataState({
    this.cachedMatched = const [],
    this.loading = false,
    this.errorMessage,
    this.isRateLimited = false,
    this.lastSyncedAt,
  });

  ContactsDataState copyWith({
    List<ContactListEntry>? cachedMatched,
    bool? loading,
    String? errorMessage,
    bool clearError = false,
    bool? isRateLimited,
    DateTime? lastSyncedAt,
  }) {
    return ContactsDataState(
      cachedMatched: cachedMatched ?? this.cachedMatched,
      loading: loading ?? this.loading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isRateLimited: isRateLimited ?? this.isRateLimited,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

class ContactsDataNotifier extends Notifier<ContactsDataState> {
  @override
  ContactsDataState build() {
    final repo = ref.read(contactsRepositoryProvider);
    final initialCache = repo.cachedMatched;

    // Asynchronously refresh in the background if contact permissions are active
    Future.microtask(() => refreshIfPermitted());

    return ContactsDataState(
      cachedMatched: initialCache ?? const [],
      lastSyncedAt: repo.lastMatchTime,
      isRateLimited: repo.isRateLimited,
    );
  }

  List<ContactListEntry> get cachedMatched => state.cachedMatched;
  bool get loading => state.loading;
  String? get errorMessage => state.errorMessage;
  bool get isRateLimited => state.isRateLimited;

  Stream<List<ContactListEntry>> watchDirectory({int limit = 1000}) =>
      ref.read(contactsRepositoryProvider).watchDirectory(limit: limit);

  Stream<List<ContactListEntry>> watchMatched({String defaultIso2 = 'IN'}) =>
      ref
          .read(contactsRepositoryProvider)
          .watchMatched(defaultIso2: defaultIso2);

  Future<void> loadMatchedContacts({bool force = false}) async {
    if (state.loading) return;

    final repo = ref.read(contactsRepositoryProvider);

    // If not forced and we have cache that is fresh, reuse existing cache
    if (!force && state.cachedMatched.isNotEmpty && !repo.isCacheExpired) {
      debugPrint('[ContactsData] Reusing fresh cached contacts (${state.cachedMatched.length} entries)');
      return;
    }

    debugPrint('[ContactsData] loading matched contacts (force=$force)...');
    state = state.copyWith(loading: true, clearError: true);

    try {
      final entries = await repo.getMatchedContacts(forceRefresh: force);
      state = state.copyWith(
        cachedMatched: List.unmodifiable(entries),
        loading: false,
        clearError: true,
        isRateLimited: false,
        lastSyncedAt: DateTime.now(),
      );
      debugPrint('[ContactsData] matched contacts updated: ${entries.length}');
    } on ContactRateLimitException catch (e) {
      debugPrint('[ContactsData] rate limit hit: ${e.message}');
      state = state.copyWith(
        loading: false,
        errorMessage: e.message,
        isRateLimited: true,
      );
    } catch (e) {
      debugPrint('[ContactsData] contact matching error: $e');
      final msg = e is ContactSyncException
          ? e.message
          : 'Unable to sync contacts right now. Please try again later.';
      state = state.copyWith(
        loading: false,
        errorMessage: msg,
        isRateLimited: false,
      );
    }
  }

  Future<void> refreshIfPermitted({bool force = false}) async {
    try {
      final granted = await Permission.contacts.isGranted;
      if (!granted) return;
      await loadMatchedContacts(force: force);
    } catch (e) {
      debugPrint('[ContactsData] Non-fatal permission check notice: $e');
    }
  }

  Future<void> triggerDebugFetchAndNotify({int limit = 50}) async {
    final contacts = await ref.read(contactsRepositoryProvider).accessService.readPhoneContacts();
    debugPrint('[ContactsDataNotifier] debug contacts fetched: ${contacts.length}');
  }
}
