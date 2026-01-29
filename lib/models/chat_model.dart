// lib/models/chat_model.dart
class ChatModel {
  final String id;
  final List<String> members;

  ChatModel({
    required this.id,
    required this.members,
  });

  factory ChatModel.fromMap(String id, Map<String, dynamic> data) {
    return ChatModel(
      id: id,
      members: List<String>.from(data['members'] ?? const []),
    );
  }
}
