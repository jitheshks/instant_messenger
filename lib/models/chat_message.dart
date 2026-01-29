import 'package:cloud_firestore/cloud_firestore.dart';
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
/// MEDIA KIND (Firestore only)
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
/// MESSAGE MEDIA MODEL (Firestore only)
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
      url: map['url'],
      kind: MediaKind.values.firstWhere((e) => e.name == map['kind']),
      mime: map['mime'],
      size: map['size'],
      thumbUrl: map['thumbUrl'],
      width: map['width'],
      height: map['height'],
      durationMs: map['durationMs'],
      fileName: map['fileName'],
    );
  }
}




/// ------------------------------------------------------------
/// 🔥 EXTENSION — MUST BE TOP LEVEL
/// ------------------------------------------------------------
extension MessageMediaCopy on MessageMedia {
  MessageMedia copyWith({
    String? url,
    MediaKind? kind,
    String? mime,
    int? size,
    String? thumbUrl, // 🔥 ADD
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
      thumbUrl: thumbUrl ?? this.thumbUrl, // 🔥 ADD
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      fileName: fileName ?? this.fileName,
    );
  }
}


/// ------------------------------------------------------------
/// CHAT MESSAGE (Hive + Firestore)
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
  this.isIncoming = false,
});


bool get hasFailed => failure != null;

bool get canRetry =>
    failure == MessageFailureReason.uploadFailed ||
    failure == MessageFailureReason.firestoreFailed;


bool get isRead => deliveryState == DeliveryState.read;

ChatMessage copyWith({
  String? id,
  String? chatId,
  String? senderId,
  String? text,
  DateTime? sentAt,
  DeliveryState? deliveryState,
  MessageType? type,
  MessageMedia? media,
  double? uploadProgress,
  MessageFailureReason? failure,
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
    uploadProgress: uploadProgress ?? this.uploadProgress,
    failure: failure ?? this.failure,
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

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'type': type.name,
      'text': text,
      if (media != null) 'media': media!.toMap(),
      'sentAt': Timestamp.fromDate(sentAt),
      'status': statusInt,
    };
  }

  static ChatMessage fromFirestore(
    String chatId,
    String id,
    Map<String, dynamic> map,
  ) {
    final ts = map['sentAt'] is Timestamp
        ? (map['sentAt'] as Timestamp).toDate()
        : DateTime.fromMillisecondsSinceEpoch(0);

    return ChatMessage(
      id: id,
      chatId: chatId,
      senderId: map['senderId'] ?? '',
      text: map['text'] ?? '',
      sentAt: ts,
      type: MessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MessageType.text,
      ),
      media: map['media'] != null
          ? MessageMedia.fromMap(Map<String, dynamic>.from(map['media']))
          : null,
      deliveryState: _deliveryFromInt(map['status'] ?? 1),
      uploadProgress: null,
          failure: null, // 🔥 IMPORTANT
      isIncoming: true,
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
  unknown,
}
