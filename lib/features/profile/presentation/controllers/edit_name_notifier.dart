import 'package:cross_file/cross_file.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class EditNameState {
  final bool showEmoji;
  final bool isSaving;
  final XFile? selectedAvatar;
  final String? errorMessage;

  const EditNameState({
    this.showEmoji = false,
    this.isSaving = false,
    this.selectedAvatar,
    this.errorMessage,
  });

  EditNameState copyWith({
    bool? showEmoji,
    bool? isSaving,
    XFile? selectedAvatar,
    String? errorMessage,
    bool clearAvatar = false,
    bool clearError = false,
  }) {
    return EditNameState(
      showEmoji: showEmoji ?? this.showEmoji,
      isSaving: isSaving ?? this.isSaving,
      selectedAvatar: clearAvatar ? null : (selectedAvatar ?? this.selectedAvatar),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class EditNameNotifier extends Notifier<EditNameState> {
  final String initial;
  late final TextEditingController textController;
  final FocusNode focusNode = FocusNode();

  EditNameNotifier(this.initial);

  @override
  EditNameState build() {
    textController = TextEditingController(text: initial);
    ref.onDispose(() {
      textController.dispose();
      focusNode.dispose();
    });
    return const EditNameState();
  }

  bool get showEmoji => state.showEmoji;
  bool get isSaving => state.isSaving;
  XFile? get selectedAvatar => state.selectedAvatar;
  String? get errorMessage => state.errorMessage;

  void showEmojiPanel(BuildContext context) {
    FocusScope.of(context).unfocus();
    state = state.copyWith(showEmoji: true);
  }

  void showKeyboard() {
    if (state.showEmoji) {
      state = state.copyWith(showEmoji: false);
    }
    Future.microtask(() => focusNode.requestFocus());
  }

  void toggleEmojiOrKeyboard(BuildContext context) {
    if (state.showEmoji) {
      showKeyboard();
    } else {
      showEmojiPanel(context);
    }
  }

  void setSelectedAvatar(XFile? file) {
    state = state.copyWith(selectedAvatar: file, clearError: true);
  }

  void setSaving(bool saving) {
    state = state.copyWith(isSaving: saving);
  }

  void setErrorMessage(String? msg) {
    state = state.copyWith(errorMessage: msg);
  }

  void onEmojiSelected(Category? category, Emoji emoji) {
    final text = textController.text + emoji.emoji;
    textController.text = text;
    textController.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
  }
}
