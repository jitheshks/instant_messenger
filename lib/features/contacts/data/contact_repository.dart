import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:instant_messenger/features/contacts/domain/models/contact_list_entry.dart';
import 'package:instant_messenger/features/contacts/domain/services/contact_identity_resolver.dart';
import 'package:instant_messenger/features/contacts/data/acess_service_contact.dart';
import 'package:instant_messenger/shared/utils/phone_format.dart';

/// Custom exception for contact synchronization errors.
class ContactSyncException implements Exception {
  final String message;
  final bool isRateLimit;
  final DateTime? resetAt;

  const ContactSyncException(
    this.message, {
    this.isRateLimit = false,
    this.resetAt,
  });

  @override
  String toString() => message;
}

/// Specialized exception for rate-limiting errors (PostgrestException code: P0001).
class ContactRateLimitException extends ContactSyncException {
  const ContactRateLimitException(
    super.message, {
    super.resetAt,
  }) : super(isRateLimit: true);
}

class ContactsRepository {
  final ContactsAccessService _access;
  final SupabaseClient? _supabaseClient;
  final String? Function()? _currentUserIdProvider;
  final Duration cacheTtl;

  List<ContactListEntry>? _cachedMatched;
  DateTime? _lastMatchTime;
  DateTime? _rateLimitResetAt;
  Future<List<ContactListEntry>>? _inFlightMatch;
  String? _lastUserId;

  ContactsRepository({
    ContactsAccessService? access,
    SupabaseClient? supabaseClient,
    String? Function()? currentUserIdProvider,
    this.cacheTtl = const Duration(minutes: 15),
  }) : _access = access ?? ContactsAccessService(),
       _supabaseClient = supabaseClient,
       _currentUserIdProvider = currentUserIdProvider;

  SupabaseClient? get _sb {
    if (_supabaseClient != null) return _supabaseClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  ContactsAccessService get accessService => _access;

  String? get currentUserId {
    if (_currentUserIdProvider != null) {
      return _currentUserIdProvider();
    }
    try {
      return _sb?.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  Box? get _contactsBox {
    try {
      if (Hive.isBoxOpen('contacts')) {
        return Hive.box('contacts');
      }
    } catch (_) {}
    return null;
  }

  void _saveMatchedToDisk(String uid, List<ContactListEntry> entries) {
    try {
      final box = _contactsBox;
      if (box != null && box.isOpen) {
        final rawList = entries.map((e) => e.toJson()).toList();
        box.put('matched_contacts_$uid', rawList);
        box.put('matched_contacts_time_$uid', DateTime.now().toIso8601String());
      }
    } catch (e) {
      debugPrint('[ContactsRepo] Error persisting matched contacts to disk: $e');
    }
  }

  List<ContactListEntry>? _loadMatchedFromDisk(String uid) {
    try {
      final box = _contactsBox;
      if (box != null && box.isOpen) {
        final raw = box.get('matched_contacts_$uid');
        if (raw is List) {
          final entries = <ContactListEntry>[];
          for (final item in raw) {
            if (item is Map) {
              entries.add(
                ContactListEntry.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
          final rawTime = box.get('matched_contacts_time_$uid');
          if (rawTime is String) {
            _lastMatchTime = DateTime.tryParse(rawTime);
          }
          return entries;
        }
      }
    } catch (e) {
      debugPrint('[ContactsRepo] Error loading matched contacts from disk: $e');
    }
    return null;
  }

  List<ContactListEntry>? get cachedMatched {
    if (_cachedMatched != null) return _cachedMatched;
    final me = currentUserId;
    if (me != null && me.isNotEmpty) {
      _cachedMatched = _loadMatchedFromDisk(me);
    }
    return _cachedMatched;
  }

  DateTime? get lastMatchTime => _lastMatchTime;
  DateTime? get rateLimitResetAt => _rateLimitResetAt;

  bool get isRateLimited =>
      _rateLimitResetAt != null && DateTime.now().isBefore(_rateLimitResetAt!);

  bool get isCacheExpired =>
      _lastMatchTime == null ||
      DateTime.now().difference(_lastMatchTime!) >= cacheTtl;

  void clearCache() {
    _cachedMatched = null;
    _lastMatchTime = null;
    _rateLimitResetAt = null;
    _inFlightMatch = null;
    _lastUserId = null;
  }

  /// Directory of all registered users (excluding current user)
  Stream<List<ContactListEntry>> watchDirectory({int limit = 1000}) {
    final me = currentUserId;
    if (me == null || me.isEmpty) {
      debugPrint('[ContactsRepo] watchDirectory: unauthenticated user');
      return Stream.value(const <ContactListEntry>[]);
    }

    final client = _sb;
    if (client == null) {
      return Stream.value(const <ContactListEntry>[]);
    }

    return client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .limit(limit)
        .map(
          (rows) => rows
              .where((r) => r['id'] != me)
              .map((r) => ContactListEntry.fromSupabase(r))
              .toList(),
        );
  }

  /// Fetches matched contacts with caching, deduplication, and rate-limit guard.
  Future<List<ContactListEntry>> getMatchedContacts({
    String defaultIso2 = 'IN',
    bool forceRefresh = false,
  }) async {
    final me = currentUserId;
    if (me == null || me.isEmpty) {
      debugPrint('[ContactsRepo] getMatchedContacts: unauthenticated user');
      return const <ContactListEntry>[];
    }

    // Account isolation: clear cache if user switched
    if (_lastUserId != null && _lastUserId != me) {
      clearCache();
    }
    _lastUserId = me;

    // 1. Rate-limit cooldown guard
    if (isRateLimited) {
      debugPrint(
        '[ContactsRepo] Rate-limit cooldown active until $_rateLimitResetAt',
      );
      if (_cachedMatched != null && !forceRefresh) {
        return _cachedMatched!;
      }
      final remainingSecs =
          _rateLimitResetAt!.difference(DateTime.now()).inSeconds;
      final minutes = (remainingSecs / 60).ceil().clamp(1, 15);
      throw ContactRateLimitException(
        'Contact sync rate limit reached. Please try again in $minutes minute${minutes == 1 ? '' : 's'}.',
        resetAt: _rateLimitResetAt,
      );
    }

    // 2. Cache reuse: if cache is fresh and not forced, return cached contacts
    if (!forceRefresh && _cachedMatched != null && !isCacheExpired) {
      debugPrint(
        '[ContactsRepo] Returning cached matched contacts (${_cachedMatched!.length} entries)',
      );
      return _cachedMatched!;
    }

    // 3. Deduplicate concurrent requests
    if (_inFlightMatch != null) {
      debugPrint('[ContactsRepo] Deduplicating concurrent match request');
      return await _inFlightMatch!;
    }

    // 4. Execute matching pipeline
    _inFlightMatch = _performMatch(me, defaultIso2: defaultIso2);
    try {
      final results = await _inFlightMatch!;
      _cachedMatched = results;
      _lastMatchTime = DateTime.now();
      _rateLimitResetAt = null; // Clear rate limit on successful sync
      _saveMatchedToDisk(me, results);
      return results;
    } finally {
      _inFlightMatch = null;
    }
  }

  Future<List<ContactListEntry>> _performMatch(
    String me, {
    required String defaultIso2,
  }) async {
    try {
      // 1. Read device contacts
      final device = await accessService.readPhoneContacts();
      debugPrint('[ContactsRepo] device entries: ${device.length}');

      // 2. Normalize numbers to E.164 format
      final pairs = <({String savedName, String? e164})>[];
      for (final d in device) {
        final e164 = await PhoneFormat.toE164(d.phoneRaw, iso2: defaultIso2);
        pairs.add((savedName: d.savedName, e164: e164));
      }

      final e164Set = pairs.map((e) => e.e164).whereType<String>().toSet();

      debugPrint(
        '[ContactsRepo] normalized pairs=${pairs.length}, '
        'e164Set size=${e164Set.length}',
      );

      if (e164Set.isEmpty) {
        return <ContactListEntry>[];
      }

      // 3. Match against Supabase via match_contacts RPC (max 200 per batch)
      final allNumbers = e164Set.toList();
      final matchedEntries = <ContactListEntry>[];
      final seenUids = <String>{};

      for (var i = 0; i < allNumbers.length; i += 200) {
        final end =
            (i + 200 < allNumbers.length) ? i + 200 : allNumbers.length;
        final chunk = allNumbers.sublist(i, end);

        final List<dynamic> rows = await _invokeRpcWithRetry(chunk);

        for (final row in rows) {
          if (row is Map) {
            final map = Map<String, dynamic>.from(row);
            final uid =
                map['id']?.toString() ?? map['uid']?.toString() ?? '';
            if (uid.isEmpty || uid == me || seenUids.contains(uid)) {
              continue; // Skip self and duplicates
            }
            seenUids.add(uid);

            final phone = map['phone_e164'] as String?;
            final saved = pairs.firstWhere(
              (p) => ContactIdentityResolver.matchPhone(p.e164, phone),
              orElse: () => (savedName: '', e164: phone),
            );
            matchedEntries.add(
              ContactListEntry.fromSupabase(
                map,
                fallbackSavedName:
                    saved.savedName.isNotEmpty ? saved.savedName : null,
              ),
            );
          }
        }
      }

      // 4. Sort alphabetically by display name
      matchedEntries.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );

      return matchedEntries;
    } on ContactSyncException {
      rethrow;
    } catch (e, st) {
      debugPrint('[ContactsRepo] _performMatch error: $e');
      debugPrintStack(stackTrace: st);
      throw ContactSyncException('Failed to match contacts: $e');
    }
  }

  /// Invokes RPC with exponential backoff on transient errors,
  /// but NEVER retries rate-limit (P0001), auth, or client validation errors.
  Future<List<dynamic>> _invokeRpcWithRetry(List<String> chunk) async {
    int attempts = 0;
    const maxAttempts = 3;
    Duration delay = const Duration(milliseconds: 500);

    while (true) {
      attempts++;
      try {
        final client = _sb;
        if (client == null) {
          throw const ContactSyncException('Supabase client unavailable');
        }
        final List<dynamic> rows = await client.rpc(
          'match_contacts',
          params: {'p_phone_numbers': chunk},
        );
        return rows;
      } on PostgrestException catch (e) {
        final isRateLimit =
            e.code == 'P0001' ||
            e.message.toLowerCase().contains('rate limit exceeded');

        if (isRateLimit) {
          // NEVER retry a rate-limit error! Set cooldown and throw immediately.
          _rateLimitResetAt =
              DateTime.now().add(const Duration(minutes: 15));
          debugPrint(
            '[ContactsRepo] Rate limit encountered from Supabase (code: ${e.code})',
          );
          throw ContactRateLimitException(
            'Contact sync rate limit reached (10 requests per 15 minutes). Please try again later.',
            resetAt: _rateLimitResetAt,
          );
        }

        // Never retry unauthorized or batch limit errors
        final isPermanent =
            e.code == '42501' ||
            e.code == '22023' ||
            e.message.toLowerCase().contains('unauthorized') ||
            e.message.toLowerCase().contains('batch limit');

        if (isPermanent || attempts >= maxAttempts) {
          throw ContactSyncException('Contact matching failed: ${e.message}');
        }

        debugPrint(
          '[ContactsRepo] Transient RPC error (attempt $attempts/$maxAttempts): ${e.message}. Retrying in ${delay.inMilliseconds}ms...',
        );
        await Future.delayed(delay);
        delay *= 2;
      } catch (e) {
        if (attempts >= maxAttempts) {
          throw ContactSyncException(
            'Network error during contact sync: $e',
          );
        }
        debugPrint(
          '[ContactsRepo] Network exception (attempt $attempts/$maxAttempts): $e. Retrying in ${delay.inMilliseconds}ms...',
        );
        await Future.delayed(delay);
        delay *= 2;
      }
    }
  }

  /// Matched contacts stream (emits cached first, then synchronizes if needed)
  Stream<List<ContactListEntry>> watchMatched({
    String defaultIso2 = 'IN',
    bool forceRefresh = false,
  }) async* {
    final me = currentUserId;
    if (me == null || me.isEmpty) {
      debugPrint('[ContactsRepo] watchMatched: unauthenticated user');
      yield const <ContactListEntry>[];
      return;
    }

    // Emit cached results immediately if available
    if (_cachedMatched != null) {
      yield _cachedMatched!;
      if (!forceRefresh && !isCacheExpired) {
        return;
      }
    }

    try {
      final entries = await getMatchedContacts(
        defaultIso2: defaultIso2,
        forceRefresh: forceRefresh,
      );
      yield entries;
    } on ContactSyncException catch (e) {
      if (_cachedMatched != null) {
        yield _cachedMatched!;
      }
      throw StateError(e.message);
    } catch (e, st) {
      debugPrint('[ContactsRepo] watchMatched error: $e');
      debugPrintStack(stackTrace: st);
      throw StateError('Contact matching failed via Supabase: $e');
    }
  }
}
