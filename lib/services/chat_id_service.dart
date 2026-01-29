// lib/services/chat_id_service.dart
class ChatIdService {
  static String oneToOne(String uidA, String uidB) {
    return (uidA.compareTo(uidB) < 0) ? '${uidA}_$uidB' : '${uidB}_$uidA';
  }
}
