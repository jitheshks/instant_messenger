// lib/features/calls/domain/services/zego_engine_service.dart

import '../models/call_enums.dart';
import '../models/zego_call_models.dart';

/// Scenario profile for media engine optimization.
enum ZegoCallScenario {
  standardCall,
  highQualityAudio;
}

/// Abstract contract for ZEGOCLOUD RTC Engine management and media streaming.
///
/// Follows Domain Layer Purity: no direct dependency on Flutter widgets,
/// Riverpod, or Supabase.
abstract class ZegoEngineService {
  /// Whether the ZEGO RTC engine has been initialized.
  bool get isInitialized;

  /// Current snapshot of the active call session.
  ZegoCallSession get currentSession;

  /// Stream of reactive updates to the [ZegoCallSession].
  Stream<ZegoCallSession> get sessionStream;

  /// Stream emitting remaining seconds when room token is about to expire.
  Stream<int> get tokenWillExpireStream;

  /// Initializes the ZEGO RTC engine singleton with the specified [appId].
  ///
  /// Safe to call multiple times with the same [appId].
  Future<void> initializeEngine({
    required int appId,
    ZegoCallScenario scenario = ZegoCallScenario.standardCall,
  });

  /// Fully releases the engine singleton and deinitializes native RTC resources.
  Future<void> destroyEngine();

  /// Logs into the authoritative room and begins media publishing.
  ///
  /// [callId] is the application call identifier.
  /// [roomId] must be the authoritative room ID returned by the backend.
  /// [userId] must be the authenticated Supabase user ID.
  /// [token] is the cryptographic Token04 returned by the backend.
  Future<void> joinRoom({
    required String callId,
    required String roomId,
    required String userId,
    required String userName,
    required String token,
    required CallType callType,
  });

  /// Leaves the current calling room and stops all local publishing/playback.
  Future<void> leaveRoom();

  /// Controls local microphone audio capture and publishing.
  Future<void> muteMicrophone(bool mute);

  /// Controls local camera video capture and publishing.
  Future<void> enableCamera(bool enable);

  /// Toggles between front and rear cameras.
  Future<void> switchCamera();

  /// Routes audio output to speakerphone ([enable] = true) or earpiece/default ([enable] = false).
  Future<void> setSpeakerphoneOn(bool enable);

  /// Renews the active room token upon [tokenWillExpireStream] emission.
  Future<void> renewToken(String token);

  /// Starts or stops local video preview with the given view ID.
  Future<void> setLocalPreviewView(int? viewId);

  /// Binds or unbinds a remote stream to a video view ID.
  Future<void> setRemoteVideoView({
    required String streamId,
    int? viewId,
  });

  /// Disposes internal streams and resets session state.
  Future<void> dispose();
}
