class ChatIdService {
  /// Legacy Firebase identifier helper that generated string pairs (`${uidA}_${uidB}`).
  ///
  /// Deprecated: In Supabase, direct chat IDs are RFC 4122 UUIDs derived via
  /// the `get_or_create_direct_chat` database RPC. Do NOT use string pairs
  /// for PostgreSQL queries as `chats.id` and `messages.chat_id` require type UUID.
  @Deprecated('Use get_or_create_direct_chat RPC to obtain canonical UUID')
  static String pair(String uidA, String uidB) {
    return (uidA.compareTo(uidB) < 0) ? '${uidA}_$uidB' : '${uidB}_$uidA';
  }

  /// Backwards-compatible alias for [pair].
  @Deprecated('Use get_or_create_direct_chat RPC to obtain canonical UUID')
  static String oneToOne(String uidA, String uidB) => pair(uidA, uidB);
}
