import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instant_messenger/core/providers/core_providers.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatTypingNotifier extends Notifier<bool> {
  final ChatControllerArgs arg;

  ChatTypingNotifier(this.arg);

  Timer? _typingTimer;
  RealtimeChannel? _channel;

  @override
  bool build() {
    final sb = ref.watch(supabaseClientProvider);

    ref.onDispose(() {
      _typingTimer?.cancel();
      if (_channel != null) {
        try {
          sb.removeChannel(_channel!);
        } catch (_) {
          _channel?.unsubscribe();
        }
        _channel = null;
      }
    });

    _channel = sb.channel(
      'chat_typing:${arg.chatId}',
      opts: const RealtimeChannelConfig(private: true),
    );

    _channel?.onBroadcast(
      event: 'typing',
      callback: (payload) {
        if (!ref.mounted) return;
        if (payload['user_id'] == arg.otherUserId) {
          final isTyping = payload['typing'] as bool? ?? false;
          state = isTyping;
        }
      },
    );

    _channel?.subscribe();

    return false;
  }

  void onTypingChanged(String text) {
    if (text.trim().isEmpty) return;

    _typingTimer?.cancel();

    _channel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': arg.currentUserId, 'typing': true},
    );

    _typingTimer = Timer(const Duration(seconds: 3), clearTyping);
  }

  void clearTyping() {
    _typingTimer?.cancel();

    _channel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': arg.currentUserId, 'typing': false},
    );
  }
}
