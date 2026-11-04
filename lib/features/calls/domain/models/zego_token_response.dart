// lib/features/calls/domain/models/zego_token_response.dart

/// Typed payload returned by the `get-zego-token` Supabase Edge Function.
class ZegoTokenResponse {
  final String token;
  final int appId;
  final String userId;
  final int expiresAt;

  const ZegoTokenResponse({
    required this.token,
    required this.appId,
    required this.userId,
    required this.expiresAt,
  });

  /// Whether the token has expired based on current local epoch seconds.
  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiresAt;

  /// Remaining valid seconds before expiration.
  int get remainingSeconds {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = expiresAt - nowSec;
    return diff > 0 ? diff : 0;
  }

  ZegoTokenResponse copyWith({
    String? token,
    int? appId,
    String? userId,
    int? expiresAt,
  }) {
    return ZegoTokenResponse(
      token: token ?? this.token,
      appId: appId ?? this.appId,
      userId: userId ?? this.userId,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  factory ZegoTokenResponse.fromJson(Map<String, dynamic> json) {
    final token = json['token'] as String?;
    final appId = json['app_id'] as int?;
    final userId = json['user_id'] as String?;
    final expiresAt = json['expires_at'] as int?;

    if (token == null || token.trim().isEmpty) {
      throw const FormatException(
        'Missing or empty "token" in ZegoTokenResponse',
      );
    }
    if (appId == null || appId <= 0) {
      throw const FormatException(
        'Missing or invalid "app_id" in ZegoTokenResponse',
      );
    }
    if (userId == null || userId.trim().isEmpty) {
      throw const FormatException(
        'Missing or empty "user_id" in ZegoTokenResponse',
      );
    }
    if (expiresAt == null || expiresAt <= 0) {
      throw const FormatException(
        'Missing or invalid "expires_at" in ZegoTokenResponse',
      );
    }

    return ZegoTokenResponse(
      token: token.trim(),
      appId: appId,
      userId: userId.trim(),
      expiresAt: expiresAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'app_id': appId,
    'user_id': userId,
    'expires_at': expiresAt,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ZegoTokenResponse &&
        other.token == token &&
        other.appId == appId &&
        other.userId == userId &&
        other.expiresAt == expiresAt;
  }

  @override
  int get hashCode => Object.hash(token, appId, userId, expiresAt);

  @override
  String toString() =>
      'ZegoTokenResponse(appId: $appId, userId: $userId, expiresAt: $expiresAt)';
}
