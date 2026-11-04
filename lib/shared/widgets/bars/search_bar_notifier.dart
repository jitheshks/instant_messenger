import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class SearchBarState {
  final bool searching;
  final String query;

  const SearchBarState({this.searching = false, this.query = ''});

  SearchBarState copyWith({bool? searching, String? query}) {
    return SearchBarState(
      searching: searching ?? this.searching,
      query: query ?? this.query,
    );
  }
}

class SearchBarNotifier extends Notifier<SearchBarState> {
  final TextEditingController text = TextEditingController();

  @override
  SearchBarState build() {
    ref.onDispose(text.dispose);
    return const SearchBarState();
  }

  bool get searching => state.searching;
  String get query => state.query;

  void start() {
    if (state.searching) return;
    state = state.copyWith(searching: true);
  }

  void stop() {
    if (!state.searching) return;
    text.clear();
    state = const SearchBarState(searching: false, query: '');
  }

  void onChanged(String v) {
    state = state.copyWith(query: v);
  }
}

final searchBarControllerProvider =
    NotifierProvider.autoDispose<SearchBarNotifier, SearchBarState>(
      SearchBarNotifier.new,
    );
