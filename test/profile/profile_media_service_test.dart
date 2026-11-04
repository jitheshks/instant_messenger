import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/profile/domain/services/profile_media_service.dart';

void main() {
  group('ProfileMediaService Domain Tests', () {
    test('Empty messages list produces an empty summary', () {
      final summary = ProfileMediaService.extractSummary([]);
      expect(summary.isEmpty, isTrue);
      expect(summary.totalCount, equals(0));
      expect(summary.mediaMessages, isEmpty);
      expect(summary.documentMessages, isEmpty);
      expect(summary.linkMessages, isEmpty);
    });

    test('Categorizes image and video media messages correctly', () {
      final messages = [
        ChatMessage(
          id: 'msg-1',
          chatId: 'chat-1',
          senderId: 'user-1',
          text: '',
          type: MessageType.media,
          sentAt: DateTime(2026, 11, 1),
          deliveryState: DeliveryState.sent,
          media: const MessageMedia(
            url: 'https://example.com/photo.jpg',
            kind: MediaKind.image,
            mime: 'image/jpeg',
            size: 1024,
          ),
        ),
        ChatMessage(
          id: 'msg-2',
          chatId: 'chat-1',
          senderId: 'user-2',
          text: '',
          type: MessageType.media,
          sentAt: DateTime(2026, 11, 2),
          deliveryState: DeliveryState.sent,
          media: const MessageMedia(
            url: 'https://example.com/video.mp4',
            kind: MediaKind.video,
            mime: 'video/mp4',
            size: 2048,
          ),
        ),
        ChatMessage(
          id: 'msg-3',
          chatId: 'chat-1',
          senderId: 'user-1',
          type: MessageType.text,
          text: 'Normal text without link',
          sentAt: DateTime(2026, 11, 3),
          deliveryState: DeliveryState.sent,
        ),
      ];

      final summary = ProfileMediaService.extractSummary(messages);
      expect(summary.totalCount, equals(2));
      expect(summary.mediaMessages.length, equals(2));
      expect(summary.documentMessages, isEmpty);
      expect(summary.linkMessages, isEmpty);
    });

    test('Categorizes document media messages correctly', () {
      final messages = [
        ChatMessage(
          id: 'msg-doc',
          chatId: 'chat-1',
          senderId: 'user-1',
          text: '',
          type: MessageType.media,
          sentAt: DateTime(2026, 11, 1),
          deliveryState: DeliveryState.sent,
          media: const MessageMedia(
            url: 'https://example.com/report.pdf',
            kind: MediaKind.document,
            mime: 'application/pdf',
            size: 512000,
            fileName: 'Annual_Report.pdf',
          ),
        ),
      ];

      final summary = ProfileMediaService.extractSummary(messages);
      expect(summary.totalCount, equals(1));
      expect(summary.documentMessages.length, equals(1));
      expect(summary.documentMessages.first.media?.fileName, equals('Annual_Report.pdf'));
    });

    test('Extracts links from message text and ignores regular text', () {
      final messages = [
        ChatMessage(
          id: 'msg-link-1',
          chatId: 'chat-1',
          senderId: 'user-1',
          type: MessageType.text,
          text: 'Check out https://flutter.dev for updates',
          sentAt: DateTime(2026, 11, 1),
          deliveryState: DeliveryState.sent,
        ),
        ChatMessage(
          id: 'msg-link-2',
          chatId: 'chat-1',
          senderId: 'user-2',
          type: MessageType.text,
          text: 'Visit http://example.org/test page',
          sentAt: DateTime(2026, 11, 2),
          deliveryState: DeliveryState.sent,
        ),
        ChatMessage(
          id: 'msg-plain',
          chatId: 'chat-1',
          senderId: 'user-1',
          type: MessageType.text,
          text: 'No web url here',
          sentAt: DateTime(2026, 11, 3),
          deliveryState: DeliveryState.sent,
        ),
      ];

      final summary = ProfileMediaService.extractSummary(messages);
      expect(summary.totalCount, equals(2));
      expect(summary.linkMessages.length, equals(2));

      expect(
        ProfileMediaService.extractFirstUrl(messages[0].text),
        equals('https://flutter.dev'),
      );
      expect(
        ProfileMediaService.extractFirstUrl(messages[1].text),
        equals('http://example.org/test'),
      );
      expect(
        ProfileMediaService.extractFirstUrl(messages[2].text),
        isNull,
      );
    });

    test('Strips trailing punctuation from extracted web links', () {
      expect(
        ProfileMediaService.extractFirstUrl('Check this out: https://flutter.dev/docs!'),
        equals('https://flutter.dev/docs'),
      );
      expect(
        ProfileMediaService.extractFirstUrl('See (https://dart.dev).'),
        equals('https://dart.dev'),
      );
      expect(
        ProfileMediaService.extractFirstUrl('Visit https://supabase.com, today;'),
        equals('https://supabase.com'),
      );
    });
  });
}
