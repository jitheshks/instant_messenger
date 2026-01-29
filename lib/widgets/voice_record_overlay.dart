import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/voice_recorder_service.dart';

class VoiceRecordOverlay extends StatelessWidget {
  const VoiceRecordOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VoiceRecorderService>(
      builder: (_, rec, _) {
        if (!rec.isRecording) return const SizedBox.shrink();

        return Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.15),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic, color: Colors.red),
                    const SizedBox(width: 12),

                    // Fake waveform
                    Expanded(
                      child: Container(
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Text(
                      _format(rec.duration),
                      style: const TextStyle(color: Colors.white),
                    ),

                    const SizedBox(width: 12),
                    const Icon(Icons.arrow_back, color: Colors.white70),
                    const SizedBox(width: 4),
                    const Text(
                      'Slide to cancel',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _format(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}


