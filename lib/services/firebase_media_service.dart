import 'dart:async';
import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

void _unawaited(Future<void> f) {} // Fire-and-forget helper

class MessageMedia {
  final String url;
  final String kind; // 'image'|'video'|'audio'|'document'
  final String? mime;
  final int size;
  final int? width;
  final int? height;
  final int? durationMs;

  const MessageMedia({
    required this.url,
    required this.kind,
    required this.size,
    this.mime,
    this.width,
    this.height,
    this.durationMs,
  });

  Map<String, dynamic> toMap() => {
        'url': url,
        'kind': kind,
        'mime': mime,
        'size': size,
        'width': width,
        'height': height,
        'durationMs': durationMs,
      }..removeWhere((k, v) => v == null);
}

class FirebaseMediaService {
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final FirebaseFirestore _db;

  FirebaseMediaService({
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    FirebaseFirestore? db,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _db = db ?? FirebaseFirestore.instance;

  /// Upload avatar to Firebase Storage and persist URL into Firestore.
  /// Returns the raw download URL. Callers can append cache-busters for UI.
  Future<String> uploadAvatarAndSaveUrl(XFile file) async {
    final local = File(file.path);
    if (!local.existsSync()) {
      debugPrint('[Avatar] Missing local file at ${file.path}');
      throw StateError('Cropped file missing at ${file.path}');
    }

    // Quick environment sanity
    final bucket = _storage.app.options.storageBucket;
    debugPrint('[Avatar] storageBucket=$bucket');
    final uid = _uidOrThrow();

    final contentType = _guessContentType(file.path);
    final size = await local.length();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final objectPath = 'user_avatars/$uid/avatar_$ts.jpg';
    final ref = _storage.ref(objectPath);

    debugPrint('[Avatar] begin uid=$uid ct=$contentType size=$size path=$objectPath');

    // Prefer short cache to avoid stale avatars on CDN/cache
    final meta = SettableMetadata(
      contentType: contentType,
      cacheControl: 'public, max-age=60',
    );

    // One retry on transient network/storage errors
    Future<TaskSnapshot> doPut() async {
      return ref
          .putFile(local, meta)
          .timeout(const Duration(seconds: 60), onTimeout: () {
        throw TimeoutException('Avatar upload timed out');
      });
    }

    try {
      TaskSnapshot task;
      try {
        task = await doPut();
      } on FirebaseException catch (e) {
        debugPrint('[Avatar] initial putFile failed: ${e.code} -> retrying once');
        task = await doPut(); // retry once
      }
      debugPrint('[Avatar] putFile state=${task.state} bytes=${task.totalBytes}');

      final url = await ref.getDownloadURL();
      debugPrint('[Avatar] downloadURL=$url');

      await _db
          .collection('users')
          .doc(uid)
          .set({'avatar_url': url, 'updated_at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      debugPrint('[Avatar] firestore updated uid=$uid');

      // Clean old avatars in background (best-effort)
      _unawaited(_cleanupOldAvatars(uid, keepLatestPath: objectPath));

      return url;
    } on FirebaseException catch (e, st) {
      debugPrint('[Avatar][FirebaseException] code=${e.code} msg=${e.message}');
      debugPrintStack(stackTrace: st);
      rethrow;
    } on TimeoutException catch (e, st) {
      debugPrint('[Avatar][Timeout] $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    } catch (e, st) {
      debugPrint('[Avatar][Error] $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  /// Uploads file to chat storage and creates a message with metadata.
  Future<void> sendMediaMessage({
    required String chatId,
    required XFile file,
    required String kind, // 'image'|'video'|'audio'|'document'
    String text = '',
  }) async {
    final uid = _uidOrThrow();
    final msgRef = _db.collection('chats').doc(chatId).collection('messages').doc();

    debugPrint('[Media] prepare chatId=$chatId msgId=${msgRef.id} kind=$kind');

    final media = await _uploadChatMedia(
      chatId: chatId,
      msgId: msgRef.id,
      file: file,
      kind: kind,
    );

    await msgRef.set({
      'senderId': uid,
      'type': kind,
      'text': text,
      'media': media.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'sent',
    });

    debugPrint('[Media] message created chatId=$chatId msgId=${msgRef.id}');
  }

  Future<MessageMedia> _uploadChatMedia({
    required String chatId,
    required String msgId,
    required XFile file,
    required String kind,
  }) async {
    final contentType = _guessContentType(file.path);
    final ext = _ext(file.path);
    final ref = _storage.ref('chat_media/$chatId/$msgId/original$ext');
    final local = File(file.path);

    final size = await local.length();
    debugPrint('[MediaUpload] chat=$chatId msg=$msgId ct=$contentType size=$size path=${ref.fullPath}');

    final task = await ref
        .putFile(local, SettableMetadata(contentType: contentType))
        .timeout(const Duration(seconds: 120), onTimeout: () {
      throw TimeoutException('Media upload timed out');
    });
    debugPrint('[MediaUpload] state=${task.state} bytes=${task.totalBytes}');

    final url = await ref.getDownloadURL();
    debugPrint('[MediaUpload] url=$url');

    return MessageMedia(
      url: url,
      kind: kind,
      size: size,
      mime: contentType,
    );
  }

  /// Clean up older avatar objects in the user's folder, keeping only the latest.
  Future<void> _cleanupOldAvatars(String uid, {required String keepLatestPath}) async {
    try {
      final prefix = _storage.ref('user_avatars/$uid');
      final list = await prefix.listAll();
      for (final item in list.items) {
        if (item.fullPath == keepLatestPath) continue;
        await item.delete();
        debugPrint('[Avatar] deleted old object ${item.fullPath}');
      }
    } catch (e) {
      // Ignore cleanup errors
      debugPrint('[Avatar] cleanup skipped: $e');
    }
  }

  // Helpers

  String _uidOrThrow() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      debugPrint('[Auth] currentUser is null');
      throw StateError('Not signed in');
    }
    return uid;
  }

  String _guessContentType(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.heic')) return 'image/heic';
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.mp4')) return 'video/mp4';
    if (p.endsWith('.mov')) return 'video/quicktime';
    if (p.endsWith('.mkv')) return 'video/x-matroska';
    if (p.endsWith('.mp3')) return 'audio/mpeg';
    if (p.endsWith('.m4a')) return 'audio/m4a';
    if (p.endsWith('.wav')) return 'audio/wav';
    if (p.endsWith('.flac')) return 'audio/flac';
    if (p.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  String _ext(String path) {
    final i = path.lastIndexOf('.');
    return i >= 0 ? path.substring(i).toLowerCase() : '';
  }
}
