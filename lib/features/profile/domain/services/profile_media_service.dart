import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';

/// Aggregated media summary for a conversation profile screen.
class ProfileMediaSummary {
  final List<ChatMessage> mediaMessages;
  final List<ChatMessage> documentMessages;
  final List<ChatMessage> linkMessages;

  const ProfileMediaSummary({
    this.mediaMessages = const [],
    this.documentMessages = const [],
    this.linkMessages = const [],
  });

  int get totalCount =>
      mediaMessages.length + documentMessages.length + linkMessages.length;

  bool get isEmpty => totalCount == 0;
}

/// Pure domain service that categorizes messages into media, documents, and links
/// for Contact Profile and Group Profile screens without downloading remote files.
class ProfileMediaService {
  static final RegExp _urlRegex = RegExp(
    r'(https?:\/\/[^\s]+)',
    caseSensitive: false,
  );

  /// Analyzes a list of messages and extracts media, documents, and web links.
  static ProfileMediaSummary extractSummary(List<ChatMessage> messages) {
    final media = <ChatMessage>[];
    final docs = <ChatMessage>[];
    final links = <ChatMessage>[];

    for (final msg in messages) {
      // 1. Media (Photos & Videos)
      if (msg.type == MessageType.media && msg.media != null) {
        final kind = msg.media!.kind;
        if (kind == MediaKind.image || kind == MediaKind.video) {
          media.add(msg);
        } else if (kind == MediaKind.document) {
          docs.add(msg);
        }
      }

      // 2. Links in message text
      if (msg.text.isNotEmpty && _urlRegex.hasMatch(msg.text)) {
        links.add(msg);
      }
    }

    return ProfileMediaSummary(
      mediaMessages: media,
      documentMessages: docs,
      linkMessages: links,
    );
  }

  /// Extracts the first web link found in a message's text, stripping trailing punctuation.
  static String? extractFirstUrl(String text) {
    final match = _urlRegex.firstMatch(text);
    if (match == null) return null;
    final raw = match.group(0)!;
    // Strip trailing punctuation often adjacent to URLs in conversational text
    return raw.replaceAll(RegExp(r'[\.,;:!?\)]+$'), '');
  }
}
