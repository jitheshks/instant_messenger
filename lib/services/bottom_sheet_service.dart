import 'package:flutter/material.dart';

class BottomSheetService {
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    bool isScrollControlled = true,
    bool useRootNavigator = true,
    Color backgroundColor = Colors.transparent,
  }) {
    final rootContext =
        Navigator.of(context, rootNavigator: true).context;

    return showModalBottomSheet<T>(
      context: rootContext,
      useRootNavigator: useRootNavigator,
      isScrollControlled: isScrollControlled,
      backgroundColor: backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => child,
    );
  }

  static void close(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}
