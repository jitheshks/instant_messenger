/// Represents a durable mutation queued in Hive CE for reliable offline-first execution.
class OutboxEntry {
  final String id;
  final String accountId;
  final String
  mutationType; // 'send_message', 'attach_media', 'promote_status', 'mark_read'
  final String targetId;
  final String payloadJson;
  final DateTime createdAt;
  final int retryCount;
  final DateTime nextAttemptAt;
  final String state; // 'queued', 'in_flight', 'exhausted'

  const OutboxEntry({
    required this.id,
    required this.accountId,
    required this.mutationType,
    required this.targetId,
    required this.payloadJson,
    required this.createdAt,
    this.retryCount = 0,
    required this.nextAttemptAt,
    this.state = 'queued',
  });

  OutboxEntry copyWith({
    String? state,
    int? retryCount,
    DateTime? nextAttemptAt,
    String? payloadJson,
  }) {
    return OutboxEntry(
      id: id,
      accountId: accountId,
      mutationType: mutationType,
      targetId: targetId,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      state: state ?? this.state,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'accountId': accountId,
    'mutationType': mutationType,
    'targetId': targetId,
    'payloadJson': payloadJson,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'retryCount': retryCount,
    'nextAttemptAt': nextAttemptAt.millisecondsSinceEpoch,
    'state': state,
  };

  factory OutboxEntry.fromMap(Map m) => OutboxEntry(
    id: m['id'] as String,
    accountId: m['accountId'] as String,
    mutationType: m['mutationType'] as String,
    targetId: m['targetId'] as String,
    payloadJson: m['payloadJson'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['createdAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    ),
    retryCount: (m['retryCount'] as int?) ?? 0,
    nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(
      (m['nextAttemptAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    ),
    state: (m['state'] as String?) ?? 'queued',
  );
}
