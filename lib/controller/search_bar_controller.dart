import 'package:flutter/material.dart';

class SearchBarController extends ChangeNotifier {
  bool _searching = false;
  String _query = '';
  final TextEditingController text = TextEditingController();

  bool get searching => _searching;
  String get query => _query;

  void start() {
    if (_searching) return;
    _searching = true;
    notifyListeners();
  }

  void stop() {
    if (!_searching) return;
    _searching = false;
    _query = '';
    text.clear();
    notifyListeners();
  }

  void onChanged(String v) {
    _query = v;
    notifyListeners();
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }
}
