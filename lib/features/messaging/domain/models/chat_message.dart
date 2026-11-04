import 'package:hive/hive.dart';

part 'chat_message.g.dart';

/// ------------------------------------------------------------
/// DELIVERY STATE (Hive-safe)
/// ------------------------------------------------------------
@HiveType(typeId: 1)
enum DeliveryState {
  @HiveField(0)
  sending,

  @HiveField(1)
  sent,

  @HiveField(2)
  delivered,

  @HiveField(3)
  read,
}

/// ------------------------------------------------------------
/// MESSAGE TYPE
/// ------------------------------------------------------------
@HiveType(typeId: 2)
enum MessageType {
  @HiveField(0)
  text,
  @HiveField(1)
  media,
  @HiveField(2)
  call,
}

/// ------------------------------------------------------------
/// MEDIA KIND
/// ------------------------------------------------------------
@HiveType(typeId: 5)
enum MediaKind {
  @HiveField(0)
  image,

  @HiveField(1)
  video,

  @HiveField(2)
  audio,

  @HiveField(3)
  document,
}

/// ------------------------------------------------------------
/// MESSAGE MEDIA MODEL
/// ------------------------------------------------------------
@HiveType(typeId: 4)
class MessageMedia {
  @HiveField(0)
  final String url;

  @HiveField(1)
  final MediaKind kind;

  @HiveField(2)
  final String mime;

  @HiveField(3)
  final int size;

  @HiveField(4)
  final String? thumbUrl;

  @HiveField(5)
  final int? width;

  @HiveField(6)
  final int? height;

  @HiveField(7)
  final int? durationMs;

  @HiveField(8)
  final String? fileName;

  const MessageMedia({
    required this.url,
    required this.kind,
    required this.mime,
    required this.size,
    this.thumbUrl,
    this.width,
    this.height,
    this.durationMs,
    this.fileName,
  });

  Map<String, dynamic> toMap() => {
    'url': url,
    'kind': kind.name,
    'mime': mime,
    'size': size,
    if (thumbUrl != null) 'thumbUrl': thumbUrl,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (durationMs != null) 'durationMs': durationMs,
    if (fileName != null) 'fileName': fileName,
  };

  factory MessageMedia.fromMap(Map<String, dynamic> map) {
    return MessageMedia(
      url: map['url'] ?? '',
      kind: MediaKind.values.firstWhere(
        (e) => e.name == map['kind'],
        orElse: () => MediaKind.image,
      ),
      mime: map['mime'] ?? 'application/octet-stream',
      size: map['size'] is int ? map['size'] as int : 0,
      thumbUrl: map['thumbUrl'],
      width: map['width'],
      height: map['height'],
      durationMs: map['durationMs'],
      fileName: map['fileName'],
    );
  }
}

/// ------------------------------------------------------------
/// EXTENSION — MUST BE TOP LEVEL
/// ------------------------------------------------------------
extension MessageMediaCopy on MessageMedia {
  MessageMedia copyWith({
    String? url,
    MediaKind? kind,
    String? mime,
    int? size,
    String? thumbUrl,
    int? width,
    int? height,
    int? durationMs,
    String? fileName,
  }) {
    return MessageMedia(
      url: url ?? this.url,
      kind: kind ?? this.kind,
      mime: mime ?? this.mime,
      size: size ?? this.size,
      thumbUrl: thumbUrl ?? this.thumbUrl,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      fileName: fileName ?? this.fileName,
    );
  }
}

/// ------------------------------------------------------------
/// CHAT MESSAGE (Hive-safe domain model)
/// ------------------------------------------------------------
@HiveType(typeId: 3)
class ChatMessage extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String chatId;

  @HiveField(2)
  final String senderId;

  @HiveField(3)
  final String text;

  @HiveField(4)
  final DateTime sentAt;

  @HiveField(5)
  final DeliveryState deliveryState;

  @HiveField(6)
  final MessageType type;

  @HiveField(7)
  final MessageMedia? media;

  @HiveField(8)
  final double? uploadProgress;

  @HiveField(9)
  final MessageFailureReason? failure;

  @HiveField(10)
  final bool isForwarded;

  @HiveField(11)
  final String? replyToMessageId;

  @HiveField(12)
  final String? replyText;

  @HiveField(13)
  final String? replySenderName;

  @HiveField(14)
  final String? replyMediaKind;

  final bool isIncoming;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.sentAt,
    required this.deliveryState,
    required this.type,
    this.media,
    this.uploadProgress,
    this.failure,
    this.isForwarded = false,
    this.replyToMessageId,
    this.replyText,
    this.replySenderName,
    this.replyMediaKind,
    this.isIncoming = false,
  });

  bool get hasFailed => failure != null;

  bool get canRetry =>
      failure == MessageFailureReason.uploadFailed ||
      failure == MessageFailureReason.firestoreFailed ||
      failure == MessageFailureReason.serverFailed;

  bool get isRead => deliveryState == DeliveryState.read;

  bool get hasReply =>
      replyToMessageId != null ||
      (replyText != null && replyText!.isNotEmpty) ||
      (replyMediaKind != null && replyMediaKind!.isNotEmpty);

  static const Object _sentinel = Object();

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? text,
    DateTime? sentAt,
    DeliveryState? deliveryState,
    MessageType? type,
    MessageMedia? media,
    Object? uploadProgress = _sentinel,
    Object? failure = _sentinel,
    bool? isForwarded,
    Object? replyToMessageId = _sentinel,
    Object? replyText = _sentinel,
    Object? replySenderName = _sentinel,
    Object? replyMediaKind = _sentinel,
    bool? isIncoming,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      sentAt: sentAt ?? this.sentAt,
      deliveryState: deliveryState ?? this.deliveryState,
      type: type ?? this.type,
      media: media ?? this.media,
      uploadProgress: identical(uploadProgress, _sentinel)
          ? this.uploadProgress
          : uploadProgress as double?,
      failure: identical(failure, _sentinel)
          ? this.failure
          : failure as MessageFailureReason?,
      isForwarded: isForwarded ?? this.isForwarded,
      replyToMessageId: identical(replyToMessageId, _sentinel)
          ? this.replyToMessageId
          : replyToMessageId as String?,
      replyText: identical(replyText, _sentinel)
          ? this.replyText
          : replyText as String?,
      replySenderName: identical(replySenderName, _sentinel)
          ? this.replySenderName
          : replySenderName as String?,
      replyMediaKind: identical(replyMediaKind, _sentinel)
          ? this.replyMediaKind
          : replyMediaKind as String?,
      isIncoming: isIncoming ?? this.isIncoming,
    );
  }

  int get statusInt {
    switch (deliveryState) {
      case DeliveryState.sending:
        return 0;
      case DeliveryState.sent:
        return 1;
      case DeliveryState.delivered:
        return 2;
      case DeliveryState.read:
        return 3;
    }
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'chatId': chatId,
    'senderId': senderId,
    'text': text,
    'sentAt': sentAt.toIso8601String(),
    'deliveryState': deliveryState.index,
    'type': type.name,
    'media': media?.toMap(),
    'failure': failure?.index,
    'isForwarded': isForwarded,
    if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
    if (replyText != null) 'replyText': replyText,
    if (replySenderName != null) 'replySenderName': replySenderName,
    if (replyMediaKind != null) 'replyMediaKind': replyMediaKind,
  };

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
    id: map['id'] as String? ?? '',
    chatId: map['chatId'] as String? ?? '',
    senderId: map['senderId'] as String? ?? '',
    text: map['text'] as String? ?? '',
    sentAt: DateTime.tryParse(map['sentAt'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    deliveryState: DeliveryState.values[(map['deliveryState'] as int?) ?? 0],
    type: MessageType.values.firstWhere(
      (e) => e.name == map['type'],
      orElse: () => MessageType.text,
    ),
    media: map['media'] != null
        ? MessageMedia.fromMap(Map<String, dynamic>.from(map['media'] as Map))
        : null,
    failure: map['failure'] != null
        ? MessageFailureReason.values[(map['failure'] as int)]
        : null,
    isForwarded: (map['isForwarded'] as bool?) ??
        (map['is_forwarded'] as bool?) ??
        false,
    replyToMessageId: (map['replyToMessageId'] ?? map['reply_to_message_id'])
        as String?,
    replyText: (map['replyText'] ?? map['reply_text']) as String?,
    replySenderName:
        (map['replySenderName'] ?? map['reply_sender_name']) as String?,
    replyMediaKind:
        (map['replyMediaKind'] ?? map['reply_media_kind']) as String?,
  );

  static ChatMessage fromSupabase(
    Map<String, dynamic> map, [
    String? currentUid,
  ]) {
    final rawSentAt = map['sent_at'];
    final sentAt = rawSentAt is String
        ? DateTime.tryParse(rawSentAt)?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        : (rawSentAt is DateTime
            ? rawSentAt.toUtc()
            : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));

    final senderId = map['sender_id'] as String? ?? '';
    final isIncoming = currentUid != null && senderId != currentUid;

    // Resolve reply snapshot if stored as jsonb or flat fields
    String? replyText;
    String? replySenderName;
    String? replyMediaKind;

    final rawSnapshot = map['reply_snapshot'];
    if (rawSnapshot is Map) {
      replyText = rawSnapshot['text'] as String?;
      replySenderName = rawSnapshot['sender_name'] as String?;
      replyMediaKind = rawSnapshot['media_kind'] as String?;
    } else {
      replyText = map['reply_text'] as String?;
      replySenderName = map['reply_sender_name'] as String?;
      replyMediaKind = map['reply_media_kind'] as String?;
    }

    final isForwarded = map['is_forwarded'] == true ||
        (rawSnapshot is Map && rawSnapshot['is_forwarded'] == true);

    return ChatMessage(
      id: map['id']?.toString() ?? '',
      chatId: map['chat_id']?.toString() ?? '',
      senderId: senderId,
      text: map['text'] as String? ?? '',
      sentAt: sentAt,
      type: MessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MessageType.text,
      ),
      media: map['media'] != null
          ? MessageMedia.fromMap(Map<String, dynamic>.from(map['media'] as Map))
          : null,
      deliveryState: _deliveryFromInt(
        map['status'] is int ? map['status'] as int : 1,
      ),
      uploadProgress: null,
      failure: null,
      isForwarded: isForwarded,
      replyToMessageId: map['reply_to_message_id']?.toString(),
      replyText: replyText,
      replySenderName: replySenderName,
      replyMediaKind: replyMediaKind,
      isIncoming: isIncoming,
    );
  }

  static DeliveryState _deliveryFromInt(int n) {
    if (n >= 3) return DeliveryState.read;
    if (n == 2) return DeliveryState.delivered;
    if (n == 1) return DeliveryState.sent;
    return DeliveryState.sending;
  }
}

@HiveType(typeId: 6)
enum MessageFailureReason {
  @HiveField(0)
  uploadFailed,

  @HiveField(1)
  firestoreFailed,

  @HiveField(2)
  unknown;

  /// Alias for server-side persistence failure during Supabase transition.
  static const MessageFailureReason serverFailed =
      MessageFailureReason.firestoreFailed;
}
