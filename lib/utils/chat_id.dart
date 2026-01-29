// lib/utils/chat_id.dart
String pairChatId(String a, String b) {
  final list = [a, b]..sort();
  return '${list.first}_${list.last}';
}
