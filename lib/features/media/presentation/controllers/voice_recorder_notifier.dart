import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class VoiceRecordState {
  final bool isRecording;
  final Duration duration;

  const VoiceRecordState({
    this.isRecording = false,
    this.duration = Duration.zero,
  });

  VoiceRecordState copyWith({bool? isRecording, Duration? duration}) {
    return VoiceRecordState(
      isRecording: isRecording ?? this.isRecording,
      duration: duration ?? this.duration,
    );
  }
}

class VoiceRecorderNotifier extends Notifier<VoiceRecordState> {
  Timer? _timer;

  @override
  VoiceRecordState build() {
    ref.onDispose(() => _timer?.cancel());
    return const VoiceRecordState();
  }

  bool get isRecording => state.isRecording;
  Duration get duration => state.duration;

  void start() {
    _timer?.cancel();
    state = const VoiceRecordState(isRecording: true, duration: Duration.zero);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(
        duration: state.duration + const Duration(seconds: 1),
      );
    });
  }

  void stop() {
    _timer?.cancel();
    state = state.copyWith(isRecording: false);
  }

  void cancel() {
    _timer?.cancel();
    state = const VoiceRecordState(isRecording: false, duration: Duration.zero);
  }
}
