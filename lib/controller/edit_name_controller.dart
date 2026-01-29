import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
// controller
class EditNameScreenController extends ChangeNotifier {
  bool _showEmoji = false;
  bool get showEmoji => _showEmoji;

  final TextEditingController textController;
  final FocusNode focusNode = FocusNode();

  EditNameScreenController({String initialText = ''})
      : textController = TextEditingController(text: initialText);

  void showEmojiPanel(BuildContext context) {
    // 1) Hide system keyboard
    FocusScope.of(context).unfocus();
    // 2) Then show emoji panel
    _showEmoji = true;
    notifyListeners();
  }

  void showKeyboard() {
    // 1) Hide emoji panel
    if (_showEmoji) {
      _showEmoji = false;
      notifyListeners();
    }
    // 2) Then focus the field to bring up the system keyboard
    Future.microtask(() => focusNode.requestFocus());
  }

  void toggleEmojiOrKeyboard(BuildContext context) {
    if (_showEmoji) {
      showKeyboard();
    } else {
      showEmojiPanel(context);
    }
  }

  void onEmojiSelected(Category? category, Emoji emoji) {
    final text = textController.text + emoji.emoji;
    textController.text = text;
    textController.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
