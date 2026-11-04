// lib/features/calls/domain/models/call_enums.dart

/// Distinguishes the media modality of a call.
enum CallType {
  audio,
  video;

  /// Serializes the enum to a stable lowercase string value.
  String toJson() => name;

  /// Parses a string representation into a [CallType], defaulting to [audio].
  static CallType fromJson(String? value) {
    if (value == null) return CallType.audio;
    return switch (value.toLowerCase().trim()) {
      'video' => CallType.video,
      _ => CallType.audio,
    };
  }
}

/// Represents the discrete lifecycle states of an audio or video call session.
enum CallStatus {
  idle,
  outgoing,
  ringing,
  connecting,
  connected,
  declined,
  cancelled,
  missed,
  ended,
  failed;

  /// Whether the call is currently in an active or establishing state.
  bool get isInProgress =>
      this == CallStatus.outgoing ||
      this == CallStatus.ringing ||
      this == CallStatus.connecting ||
      this == CallStatus.connected;

  /// Whether the call has reached a terminal state.
  bool get isTerminated =>
      this == CallStatus.idle ||
      this == CallStatus.declined ||
      this == CallStatus.cancelled ||
      this == CallStatus.missed ||
      this == CallStatus.ended ||
      this == CallStatus.failed;

  /// Serializes the enum to a stable lowercase string value.
  String toJson() => name;

  /// Parses a string representation into a [CallStatus], defaulting to [idle].
  static CallStatus fromJson(String? value) {
    if (value == null) return CallStatus.idle;
    final normalized = value.toLowerCase().trim();
    if (normalized == 'ongoing') return CallStatus.connected;
    for (final status in CallStatus.values) {
      if (status.name.toLowerCase() == normalized) {
        return status;
      }
    }
    return CallStatus.idle;
  }
}
