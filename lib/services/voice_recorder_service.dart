import 'dart:async';
import 'package:flutter/foundation.dart';

class VoiceRecorderService extends ChangeNotifier {
  bool _recording = false;
  Duration _duration = Duration.zero;
  Timer? _timer;

  bool get isRecording => _recording;
  Duration get duration => _duration;

  void start() {
    _recording = true;
    _duration = Duration.zero;
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _duration += const Duration(seconds: 1);
      notifyListeners();
    });

    notifyListeners();
  }

  void stop() {
    _timer?.cancel();
    _recording = false;
    notifyListeners();
  }

  void cancel() {
    _timer?.cancel();
    _duration = Duration.zero;
    _recording = false;
    notifyListeners();
  }
}
