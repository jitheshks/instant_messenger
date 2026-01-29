import 'selection_controller.dart';

/// Selection controller for the Chats tab (thread selection by chatId).
class ChatsTabSelectionController extends SelectionController<String> {
  // Extend with thread‑level batch actions if needed, e.g.:
  // Future<void> muteSelected(ChatsRepository repo, {required bool value});
  // Future<void> deleteSelected(ChatsRepository repo);
  // Future<void> markReadSelected(ChatsRepository repo);
}
