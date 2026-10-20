import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';

class SearchState {
  final String query;
  final List<Song> results;
  final bool isLoading;
  final String? error;

  const SearchState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.error,
  });

  SearchState copyWith({
    String? query,
    List<Song>? results,
    bool? isLoading,
    String? error,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class SearchControllerNotifier extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();
}
