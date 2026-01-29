// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MessageMediaAdapter extends TypeAdapter<MessageMedia> {
  @override
  final int typeId = 4;

  @override
  MessageMedia read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MessageMedia(
      url: fields[0] as String,
      kind: fields[1] as MediaKind,
      mime: fields[2] as String,
      size: fields[3] as int,
      thumbUrl: fields[4] as String?,
      width: fields[5] as int?,
      height: fields[6] as int?,
      durationMs: fields[7] as int?,
      fileName: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, MessageMedia obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.url)
      ..writeByte(1)
      ..write(obj.kind)
      ..writeByte(2)
      ..write(obj.mime)
      ..writeByte(3)
      ..write(obj.size)
      ..writeByte(4)
      ..write(obj.thumbUrl)
      ..writeByte(5)
      ..write(obj.width)
      ..writeByte(6)
      ..write(obj.height)
      ..writeByte(7)
      ..write(obj.durationMs)
      ..writeByte(8)
      ..write(obj.fileName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageMediaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = 3;

  @override
  ChatMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatMessage(
      id: fields[0] as String,
      chatId: fields[1] as String,
      senderId: fields[2] as String,
      text: fields[3] as String,
      sentAt: fields[4] as DateTime,
      deliveryState: fields[5] as DeliveryState,
      type: fields[6] as MessageType,
      media: fields[7] as MessageMedia?,
      uploadProgress: fields[8] as double?,
      failure: fields[9] as MessageFailureReason?,
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.chatId)
      ..writeByte(2)
      ..write(obj.senderId)
      ..writeByte(3)
      ..write(obj.text)
      ..writeByte(4)
      ..write(obj.sentAt)
      ..writeByte(5)
      ..write(obj.deliveryState)
      ..writeByte(6)
      ..write(obj.type)
      ..writeByte(7)
      ..write(obj.media)
      ..writeByte(8)
      ..write(obj.uploadProgress)
      ..writeByte(9)
      ..write(obj.failure);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class DeliveryStateAdapter extends TypeAdapter<DeliveryState> {
  @override
  final int typeId = 1;

  @override
  DeliveryState read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return DeliveryState.sending;
      case 1:
        return DeliveryState.sent;
      case 2:
        return DeliveryState.delivered;
      case 3:
        return DeliveryState.read;
      default:
        return DeliveryState.sending;
    }
  }

  @override
  void write(BinaryWriter writer, DeliveryState obj) {
    switch (obj) {
      case DeliveryState.sending:
        writer.writeByte(0);
        break;
      case DeliveryState.sent:
        writer.writeByte(1);
        break;
      case DeliveryState.delivered:
        writer.writeByte(2);
        break;
      case DeliveryState.read:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeliveryStateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MessageTypeAdapter extends TypeAdapter<MessageType> {
  @override
  final int typeId = 2;

  @override
  MessageType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MessageType.text;
      case 1:
        return MessageType.media;
      case 2:
        return MessageType.call;
      default:
        return MessageType.text;
    }
  }

  @override
  void write(BinaryWriter writer, MessageType obj) {
    switch (obj) {
      case MessageType.text:
        writer.writeByte(0);
        break;
      case MessageType.media:
        writer.writeByte(1);
        break;
      case MessageType.call:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MediaKindAdapter extends TypeAdapter<MediaKind> {
  @override
  final int typeId = 5;

  @override
  MediaKind read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MediaKind.image;
      case 1:
        return MediaKind.video;
      case 2:
        return MediaKind.audio;
      case 3:
        return MediaKind.document;
      default:
        return MediaKind.image;
    }
  }

  @override
  void write(BinaryWriter writer, MediaKind obj) {
    switch (obj) {
      case MediaKind.image:
        writer.writeByte(0);
        break;
      case MediaKind.video:
        writer.writeByte(1);
        break;
      case MediaKind.audio:
        writer.writeByte(2);
        break;
      case MediaKind.document:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaKindAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MessageFailureReasonAdapter extends TypeAdapter<MessageFailureReason> {
  @override
  final int typeId = 6;

  @override
  MessageFailureReason read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MessageFailureReason.uploadFailed;
      case 1:
        return MessageFailureReason.firestoreFailed;
      case 2:
        return MessageFailureReason.unknown;
      default:
        return MessageFailureReason.uploadFailed;
    }
  }

  @override
  void write(BinaryWriter writer, MessageFailureReason obj) {
    switch (obj) {
      case MessageFailureReason.uploadFailed:
        writer.writeByte(0);
        break;
      case MessageFailureReason.firestoreFailed:
        writer.writeByte(1);
        break;
      case MessageFailureReason.unknown:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageFailureReasonAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
