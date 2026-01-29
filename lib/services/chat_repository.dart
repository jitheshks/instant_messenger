import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:instant_messenger/models/chat_message.dart';
import 'package:instant_messenger/models/chat_model.dart';

class ChatRepository {
  final FirebaseFirestore _db;

  ChatRepository({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  static String pairChatId(String a, String b) {
    final list = [a, b]..sort();
    return '${list.first}_${list.last}';
  }

  Future<List<ChatMessage>> loadLatestMessages(
    String chatId, {
    int limit = 30,
  }) async {
    final snap = await _baseMessageQuery(chatId).limit(limit).get();

    return snap.docs
        .map((d) => ChatMessage.fromFirestore(chatId, d.id, d.data()))
        .toList();
  }

  Future<List<ChatMessage>> loadOlderMessages(
    String chatId,
    DocumentSnapshot lastDoc, {
    int limit = 30,
  }) async {
    final snap = await _baseMessageQuery(
      chatId,
    ).startAfterDocument(lastDoc).limit(limit).get();

    return snap.docs
        .map((d) => ChatMessage.fromFirestore(chatId, d.id, d.data()))
        .toList();
  }

  // ---------------- CHAT DOC ----------------

  Future<void> ensureChatDoc({
    required String chatId,
    required String uidA,
    required String uidB,
    required String title,
    String? avatarUrl,
  }) async {
    final members = {uidA, uidB}.toList();

    if (members.length != 2) {
      throw Exception('Chat must have exactly 2 members');
    }

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) {
      throw FirebaseAuthException(
        code: 'not-authenticated',
        message: 'User must be signed in',
      );
    }

    final otherUid = members.firstWhere((m) => m != myUid);

    final chatRef = _db.collection('chats').doc(chatId);
    final mySummary = _db
        .collection('users')
        .doc(myUid)
        .collection('chats')
        .doc(chatId);

    // 🔥 NO READS — WRITE ONLY
    await chatRef.set({
      'id': chatId,
      'members': members,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastTime': FieldValue.serverTimestamp(),
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
    }, SetOptions(merge: true));

    await mySummary.set({
      'title': title,
      'members': members,
      'otherUserId': otherUid,
      'unread': 0,
      'muted': false,
    }, SetOptions(merge: true));
  }

  // ---------------- STREAM ----------------

  Stream<List<ChatMessage>> watchChat(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('sentAt', isNotEqualTo: null) // 🔥 REQUIRED
        .orderBy('sentAt')
        .snapshots()
        .map(
          (qs) => qs.docs
              .map((d) => ChatMessage.fromFirestore(chatId, d.id, d.data()))
              .toList(),
        );
  }

  Query<Map<String, dynamic>> _baseMessageQuery(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('sentAt', isNotEqualTo: null)
        .orderBy('sentAt', descending: true);
  }

  // ---------------- SEND ----------------

  Future<String> sendMessage(
    String chatId,
    ChatMessage msg, {
    required String otherUserId,
    required String otherName,
    String? otherAvatar,
  }) async {
    final me = msg.senderId;

    await ensureChatDoc(
      chatId: chatId,
      uidA: me,
      uidB: otherUserId,
      title: otherName,
      avatarUrl: otherAvatar,
    );

    final refMsg = _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(msg.id);

    final refChat = _db.collection('chats').doc(chatId);

    final mySummary = _db
        .collection('users')
        .doc(me)
        .collection('chats')
        .doc(chatId);

    final otherSummary = _db
        .collection('users')
        .doc(otherUserId)
        .collection('chats')
        .doc(chatId);

    final last = switch (msg.type) {
      MessageType.text => msg.text,
      MessageType.media => _mediaLabel(msg.media),
      MessageType.call => 'Call',
    };

    final batch = _db.batch();

    // 1️⃣ message
    batch.set(refMsg, {
      'senderId': me,
      'type': msg.type.name,
      'text': msg.text,
      if (msg.media != null) 'media': msg.media!.toMap(),
      'sentAt': FieldValue.serverTimestamp(),
      'status': DeliveryState.sent.index,
    });

    // 2️⃣ global chat
    batch.set(refChat, {
      'lastMessage': last,
      'lastTime': FieldValue.serverTimestamp(), // ✅ FIX
    }, SetOptions(merge: true));

    // 3️⃣ sender summary
    batch.set(mySummary, {
      'title': otherName,
      'otherUserId': otherUserId,
      'lastMessage': last,
      'lastTime': FieldValue.serverTimestamp(),
      'unread': 0,
      'lastSenderId': me,
      'lastMessageStatus': DeliveryState.sent.index,
    }, SetOptions(merge: true));

    // 4️⃣ receiver summary
    batch.set(otherSummary, {
      'title': FirebaseAuth.instance.currentUser?.displayName ?? 'Chat',
      'otherUserId': me,
      'lastMessage': last,
      'lastTime': FieldValue.serverTimestamp(),
      'unread': FieldValue.increment(1),
      'lastSenderId': me,
      'lastMessageStatus': DeliveryState.sent.index,
    }, SetOptions(merge: true));

    await batch.commit();
    return refMsg.id;
  }

  // ---------------- STATUS ----------------

  Future<void> promoteStatusBatch({
    required String chatId,
    required List<String> messageIds,
    required int newStatus,
  }) async {
    final batch = _db.batch();
    final col = _db.collection('chats').doc(chatId).collection('messages');

    for (final id in messageIds) {
      batch.update(col.doc(id), {'status': newStatus});
    }

    await batch.commit();
  }

  Future<void> markRead(String chatId, String readerUid) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final chatSnap = await chatRef.get();
    if (!chatSnap.exists) return;

    final members =
        (chatSnap.data()?['members'] as List?)?.cast<String>() ?? [];
    if (members.length != 2) return;

    // 🔥 Sender is the OTHER user, not inferred from messages
    final senderUid = members.firstWhere((m) => m != readerUid);

    final unreadMsgs = await chatRef
        .collection('messages')
        .where('senderId', isEqualTo: senderUid)
        .where('status', isLessThan: DeliveryState.read.index)
        .get();

    if (unreadMsgs.docs.isEmpty) return;

    final batch = _db.batch();

    // 1️⃣ Mark messages as SEEN
    for (final d in unreadMsgs.docs) {
      batch.update(d.reference, {'status': DeliveryState.read.index});
    }

    // 2️⃣ Reader summary
    batch.set(
      _db.collection('users').doc(readerUid).collection('chats').doc(chatId),
      {'unread': 0},
      SetOptions(merge: true),
    );

    // 3️⃣ 🔥 Sender summary (blue tick sync across devices)
    batch.set(
      _db.collection('users').doc(senderUid).collection('chats').doc(chatId),
      {'lastMessageStatus': DeliveryState.read.index},
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  Future<String?> getDisplayName(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return doc.data()?['displayName'];
    } catch (_) {
      return null;
    }
  }

  Future<void> markDeliveredIfNeeded({
    required String chatId,
    required String currentUserId,
    required List<ChatMessage> messages,
  }) async {
    final toDeliver = messages
        .where(
          (m) =>
              m.senderId != currentUserId &&
              m.deliveryState.index < DeliveryState.delivered.index,
        )
        .toList();

    if (toDeliver.isEmpty) return;

    final senderId = toDeliver.first.senderId;

    await promoteStatusBatch(
      chatId: chatId,
      messageIds: toDeliver.map((m) => m.id).toList(),
      newStatus: DeliveryState.delivered.index,
    );

    // ✅ UPDATE SENDER SUMMARY
    await _db
        .collection('users')
        .doc(senderId)
        .collection('chats')
        .doc(chatId)
        .set({
          'lastMessageStatus': DeliveryState.delivered.index,
        }, SetOptions(merge: true));
  }

  String _mediaLabel(MessageMedia? media) {
    if (media == null) return 'Media';
    switch (media.kind) {
      case MediaKind.image:
        return 'Photo';
      case MediaKind.video:
        return 'Video';
      case MediaKind.audio:
        return 'Audio';
      case MediaKind.document:
        return 'Document';
    }
  }

  Future<ChatModel> getChat(String chatId) async {
    final snap = await _db.collection('chats').doc(chatId).get();
    if (!snap.exists) {
      throw Exception('Chat not found');
    }
    return ChatModel.fromMap(snap.id, snap.data()!);
  }
}
