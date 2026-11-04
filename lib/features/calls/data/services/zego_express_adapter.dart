// lib/features/calls/data/services/zego_express_adapter.dart

import 'package:flutter/widgets.dart';
import 'package:zego_express_engine/zego_express_engine.dart';

/// Abstract adapter interface wrapping [ZegoExpressEngine] static and instance methods.
///
/// Enables dependency injection, isolated testing, and headless execution
/// without crashing on environments without native RTC libraries.
abstract class ZegoExpressAdapter {
  Future<void> createEngineWithProfile(ZegoEngineProfile profile);
  Future<void> destroyEngine();
  Future<ZegoRoomLoginResult> loginRoom(String roomID, ZegoUser user, {ZegoRoomConfig? config});
  Future<ZegoRoomLogoutResult> logoutRoom([String? roomID]);
  Future<void> renewToken(String roomID, String token);
  Future<void> startPublishingStream(String streamID, {ZegoPublisherConfig? config, ZegoPublishChannel? channel});
  Future<void> stopPublishingStream({ZegoPublishChannel? channel});
  Future<void> startPreview({ZegoCanvas? canvas, ZegoPublishChannel? channel});
  Future<void> stopPreview({ZegoPublishChannel? channel});
  Future<void> startPlayingStream(String streamID, {ZegoCanvas? canvas, ZegoPlayerConfig? config});
  Future<void> stopPlayingStream(String streamID);
  Future<void> muteMicrophone(bool mute);
  Future<void> muteSpeaker(bool mute);
  Future<void> enableCamera(bool enable, {ZegoExpNotifyDeviceStateMode? notifyMode, ZegoPublishChannel? channel});
  Future<void> useFrontCamera(bool enable, {ZegoPublishChannel? channel});
  Future<void> setAudioRouteToSpeaker(bool defaultToSpeaker);
  Future<Widget?> createCanvasView(Function(int viewID) onViewCreated, {Key? key, dynamic args});
  Future<bool> destroyCanvasView(int viewID);

  // Event handler registration
  void registerCallbacks({
    void Function(String roomID, ZegoRoomStateChangedReason reason, int errorCode, Map<String, dynamic> extendedData)? onRoomStateChanged,
    void Function(String roomID, ZegoUpdateType updateType, List<ZegoUser> userList)? onRoomUserUpdate,
    void Function(String roomID, ZegoUpdateType updateType, List<ZegoStream> streamList, Map<String, dynamic> extendedData)? onRoomStreamUpdate,
    void Function(String roomID, int remainTimeInSecond)? onRoomTokenWillExpire,
    void Function(String streamID, ZegoPublisherState state, int errorCode, Map<String, dynamic> extendedData)? onPublisherStateUpdate,
    void Function(String streamID, ZegoPlayerState state, int errorCode, Map<String, dynamic> extendedData)? onPlayerStateUpdate,
  });

  void clearCallbacks();
}

/// Production implementation of [ZegoExpressAdapter] routing directly to [ZegoExpressEngine].
class DefaultZegoExpressAdapter implements ZegoExpressAdapter {
  @override
  Future<void> createEngineWithProfile(ZegoEngineProfile profile) async {
    return await ZegoExpressEngine.createEngineWithProfile(profile);
  }

  @override
  Future<void> destroyEngine() async {
    return await ZegoExpressEngine.destroyEngine();
  }

  @override
  Future<ZegoRoomLoginResult> loginRoom(String roomID, ZegoUser user, {ZegoRoomConfig? config}) async {
    return await ZegoExpressEngine.instance.loginRoom(roomID, user, config: config);
  }

  @override
  Future<ZegoRoomLogoutResult> logoutRoom([String? roomID]) async {
    return await ZegoExpressEngine.instance.logoutRoom(roomID);
  }

  @override
  Future<void> renewToken(String roomID, String token) async {
    return await ZegoExpressEngine.instance.renewToken(roomID, token);
  }

  @override
  Future<void> startPublishingStream(String streamID, {ZegoPublisherConfig? config, ZegoPublishChannel? channel}) async {
    return await ZegoExpressEngine.instance.startPublishingStream(streamID, config: config, channel: channel);
  }

  @override
  Future<void> stopPublishingStream({ZegoPublishChannel? channel}) async {
    return await ZegoExpressEngine.instance.stopPublishingStream(channel: channel);
  }

  @override
  Future<void> startPreview({ZegoCanvas? canvas, ZegoPublishChannel? channel}) async {
    return await ZegoExpressEngine.instance.startPreview(canvas: canvas, channel: channel);
  }

  @override
  Future<void> stopPreview({ZegoPublishChannel? channel}) async {
    return await ZegoExpressEngine.instance.stopPreview(channel: channel);
  }

  @override
  Future<void> startPlayingStream(String streamID, {ZegoCanvas? canvas, ZegoPlayerConfig? config}) async {
    return await ZegoExpressEngine.instance.startPlayingStream(streamID, canvas: canvas, config: config);
  }

  @override
  Future<void> stopPlayingStream(String streamID) async {
    return await ZegoExpressEngine.instance.stopPlayingStream(streamID);
  }

  @override
  Future<void> muteMicrophone(bool mute) async {
    return await ZegoExpressEngine.instance.muteMicrophone(mute);
  }

  @override
  Future<void> muteSpeaker(bool mute) async {
    return await ZegoExpressEngine.instance.muteSpeaker(mute);
  }

  @override
  Future<void> enableCamera(bool enable, {ZegoExpNotifyDeviceStateMode? notifyMode, ZegoPublishChannel? channel}) async {
    return await ZegoExpressEngine.instance.enableCamera(enable, notifyMode: notifyMode, channel: channel);
  }

  @override
  Future<void> useFrontCamera(bool enable, {ZegoPublishChannel? channel}) async {
    return await ZegoExpressEngine.instance.useFrontCamera(enable, channel: channel);
  }

  @override
  Future<void> setAudioRouteToSpeaker(bool defaultToSpeaker) async {
    return await ZegoExpressEngine.instance.setAudioRouteToSpeaker(defaultToSpeaker);
  }

  @override
  Future<Widget?> createCanvasView(Function(int viewID) onViewCreated, {Key? key, dynamic args}) async {
    return await ZegoExpressEngine.instance.createCanvasView(onViewCreated, key: key, args: args);
  }

  @override
  Future<bool> destroyCanvasView(int viewID) async {
    return await ZegoExpressEngine.instance.destroyCanvasView(viewID);
  }

  @override
  void registerCallbacks({
    void Function(String roomID, ZegoRoomStateChangedReason reason, int errorCode, Map<String, dynamic> extendedData)? onRoomStateChanged,
    void Function(String roomID, ZegoUpdateType updateType, List<ZegoUser> userList)? onRoomUserUpdate,
    void Function(String roomID, ZegoUpdateType updateType, List<ZegoStream> streamList, Map<String, dynamic> extendedData)? onRoomStreamUpdate,
    void Function(String roomID, int remainTimeInSecond)? onRoomTokenWillExpire,
    void Function(String streamID, ZegoPublisherState state, int errorCode, Map<String, dynamic> extendedData)? onPublisherStateUpdate,
    void Function(String streamID, ZegoPlayerState state, int errorCode, Map<String, dynamic> extendedData)? onPlayerStateUpdate,
  }) {
    ZegoExpressEngine.onRoomStateChanged = onRoomStateChanged;
    ZegoExpressEngine.onRoomUserUpdate = onRoomUserUpdate;
    ZegoExpressEngine.onRoomStreamUpdate = onRoomStreamUpdate;
    ZegoExpressEngine.onRoomTokenWillExpire = onRoomTokenWillExpire;
    ZegoExpressEngine.onPublisherStateUpdate = onPublisherStateUpdate;
    ZegoExpressEngine.onPlayerStateUpdate = onPlayerStateUpdate;
  }

  @override
  void clearCallbacks() {
    ZegoExpressEngine.onRoomStateChanged = null;
    ZegoExpressEngine.onRoomUserUpdate = null;
    ZegoExpressEngine.onRoomStreamUpdate = null;
    ZegoExpressEngine.onRoomTokenWillExpire = null;
    ZegoExpressEngine.onPublisherStateUpdate = null;
    ZegoExpressEngine.onPlayerStateUpdate = null;
  }
}
