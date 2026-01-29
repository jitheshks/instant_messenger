// lib/controller/chat_typing_controller.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatTypingController {
  final String chatId;
  final String currentUserId;

  Timer? _typingTimer;

  ChatTypingController({
    required this.chatId,
    required this.currentUserId,
  });

  /// Called on text change
  void onTypingChanged(String text) {
    if (text.trim().isEmpty) return;

    _typingTimer?.cancel();

    FirebaseFirestore.instance
        .collection('typing')
        .doc(chatId)
        .collection('users')
        .doc(currentUserId)
        .set({
          'typing': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    // Auto-clear after 3 seconds
    _typingTimer = Timer(const Duration(seconds: 3), clearTyping);
  }

  /// Force-clear typing
  void clearTyping() {
    _typingTimer?.cancel();

    FirebaseFirestore.instance
        .collection('typing')
        .doc(chatId)
        .collection('users')
        .doc(currentUserId)
        .delete();
  }

  /// Watch OTHER user's typing
  Stream<bool> watchTyping(String otherUserId) {
    return FirebaseFirestore.instance
        .collection('typing')
        .doc(chatId)
        .collection('users')
        .doc(otherUserId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return false;

          final ts = doc.data()?['updatedAt'] as Timestamp?;
          if (ts == null) return false;

          return DateTime.now().difference(ts.toDate()).inSeconds < 3;
        });
  }

  void dispose() {
    _typingTimer?.cancel();
  }
}
