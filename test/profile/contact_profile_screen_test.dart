import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/auth/presentation/providers/auth_providers.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/profile/domain/models/contact_profile_details.dart';
import 'package:instant_messenger/features/profile/domain/services/profile_media_service.dart';
import 'package:instant_messenger/features/profile/presentation/controllers/contact_profile_notifier.dart';
import 'package:instant_messenger/features/profile/presentation/providers/profile_screen_providers.dart';
import 'package:instant_messenger/features/profile/presentation/screens/contact_profile_screen.dart';

class FakeContactProfileNotifier extends ContactProfileNotifier {
  final ContactProfileDetails mockDetails;

  FakeContactProfileNotifier(super.arg, this.mockDetails);

  @override
  ContactProfileState build() {
    return ContactProfileState(
      isLoading: false,
      details: mockDetails,
    );
  }

  @override
  Future<void> toggleMute(String currentUserId, bool isMuted) async {
    state = state.copyWith(
      details: state.details?.copyWith(isMuted: isMuted),
    );
  }

  @override
  Future<void> clearChat() async {
    state = state.copyWith(
      details: state.details?.copyWith(
        mediaSummary: const ProfileMediaSummary(),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testArgs = const ContactProfileArgs(
    chatId: 'chat-100',
    peerUserId: 'user-peer-1',
    currentUserId: 'user-me',
    initialName: 'User A-1',
    initialPhone: '+919645905577',
  );

  final testDetails = ContactProfileDetails(
    chatId: 'chat-100',
    peerUserId: 'user-peer-1',
    resolvedDisplayName: 'User A-1',
    phoneE164: '+919645905577',
    about: 'Available',
    isMuted: false,
    mediaSummary: ProfileMediaSummary(
      mediaMessages: [
        ChatMessage(
          id: 'm1',
          chatId: 'chat-100',
          senderId: 'user-peer-1',
          text: '',
          type: MessageType.media,
          sentAt: DateTime(2026, 11, 1),
          deliveryState: DeliveryState.sent,
          media: const MessageMedia(
            url: 'https://example.com/p.jpg',
            kind: MediaKind.image,
            mime: 'image/jpeg',
            size: 1024,
          ),
        ),
      ],
      linkMessages: [
        ChatMessage(
          id: 'm2',
          chatId: 'chat-100',
          senderId: 'user-peer-1',
          type: MessageType.text,
          text: 'https://google.com',
          sentAt: DateTime(2026, 11, 2),
          deliveryState: DeliveryState.sent,
        ),
      ],
    ),
  );

  Widget buildTestApp({ContactProfileDetails? details}) {
    final d = details ?? testDetails;
    return ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('user-me'),
        contactProfileControllerProvider(testArgs).overrideWith(
          () => FakeContactProfileNotifier(testArgs, d),
        ),
      ],
      child: const MaterialApp(
        home: ContactProfileScreen(
          chatId: 'chat-100',
          peerUserId: 'user-peer-1',
          peerName: 'User A-1',
          phone: '+919645905577',
        ),
      ),
    );
  }

  group('ContactProfileScreen Widget Tests', () {
    testWidgets('Renders contact header, resolved name, phone, and about status', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Contact info'), findsOneWidget);
      expect(find.text('User A-1'), findsOneWidget);
      expect(find.text('+919645905577'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
    });

    testWidgets('Renders quick actions: Audio, Video, Search', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.byIcon(Icons.call_outlined), findsOneWidget);
      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('Renders media, links, and docs section with count', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Media, links, and docs'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // 1 media + 1 link
    });

    testWidgets('Renders settings card with Mute switch and Encryption info', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Mute notifications'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Encryption'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Encryption'), findsOneWidget);
      expect(find.text('Protected by Transport Layer Security & RLS'), findsOneWidget);

      // Tapping Encryption info opens security dialog
      await tester.tap(find.text('Encryption'));
      await tester.pumpAndSettle();

      expect(find.text('Security Details'), findsOneWidget);
      expect(
        find.textContaining('Your messages and calls are transported using encrypted TLS connections'),
        findsOneWidget,
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('Destructive action Clear chat requires confirmation', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Clear chat'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Clear chat'));
      await tester.pumpAndSettle();

      expect(find.text('Clear this chat?'), findsOneWidget);
      expect(
        find.textContaining('Messages will only be cleared from this device'),
        findsOneWidget,
      );

      // Tap cancel dismisses without clearing
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Clear this chat?'), findsNothing);
    });

    testWidgets('Destructive action Block requires confirmation dialog', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Block User A-1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Block User A-1'));
      await tester.pumpAndSettle();

      expect(find.text('Block User A-1?'), findsOneWidget);
      expect(
        find.text('This feature is not available yet.'),
        findsOneWidget,
      );

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Block User A-1?'), findsNothing);
    });

    testWidgets('Destructive action Report requires confirmation dialog', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Report User A-1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Report User A-1'));
      await tester.pumpAndSettle();

      expect(find.text('Report User A-1?'), findsOneWidget);
      expect(
        find.text('This feature is not available yet.'),
        findsOneWidget,
      );

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Report User A-1?'), findsNothing);
    });
  });
}
