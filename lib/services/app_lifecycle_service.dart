import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'outbox_service.dart';
import 'background_upload_resync.dart';

class AppLifecycleService extends WidgetsBindingObserver {
  static final AppLifecycleService _instance = AppLifecycleService._();
  factory AppLifecycleService() => _instance;
  AppLifecycleService._();

  bool _registered = false;
  OutboxService? _outbox;

  /// attach after bootstrap
  void attachOutbox(OutboxService outbox) {
    _outbox = outbox;
  }

  void register() {
    if (_registered) return;
    WidgetsBinding.instance.addObserver(this);
    _registered = true;

    if (kDebugMode) {
      debugPrint('[Lifecycle] registered');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final isOnline = state == AppLifecycleState.resumed;

    // presence (optional but OK)
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set(
      {
        'online': isOnline,
        if (!isOnline) 'lastSeen': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // 🔥 THIS is where resync happens
    if ((state == AppLifecycleState.paused ||
         state == AppLifecycleState.detached) &&
        _outbox != null) {
      BackgroundUploadResync.resync(_outbox!);
    }
  }
}
