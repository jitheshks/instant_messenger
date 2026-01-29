import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class PushSenderClient {
  final Uri? endpoint;
  final String? sharedSecret;

  PushSenderClient({required this.endpoint, required this.sharedSecret});

  bool get isConfigured => endpoint != null && (sharedSecret?.isNotEmpty ?? false);

  Future<bool> sendChat({
    required String chatId,
    required String senderId,
    required String preview,
    String type = 'text',
  }) async {
    if (!isConfigured) {
      debugPrint('[PushSender] skipped: not configured');
      return false;
    }

    final res = await http.post(
      endpoint!,
      headers: {
        'Content-Type': 'application/json',
        'x-sender-secret': sharedSecret!,
      },
      body: jsonEncode({
        'chatId': chatId,
        'senderId': senderId,
        'preview': preview,
        'type': type,
      }),
    );

    debugPrint('[PushSender] status=${res.statusCode} body=${res.body}');
    return res.statusCode >= 200 && res.statusCode < 300;
  }
}
