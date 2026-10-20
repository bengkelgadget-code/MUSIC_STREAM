import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../models/song.dart';
import '../services/youtube_service.dart';
import 'providers.dart';

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
    bool clearError = false,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SearchControllerNotifier extends Notifier<SearchState> {
  late final YouTubeService _youTubeService;

  @override
  SearchState build() {
    _youTubeService = ref.watch(youtubeServiceProvider);
    return const SearchState();
  }

  Future<void> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      state = const SearchState();
      return;
    }

    state = state.copyWith(
      query: cleanQuery,
      isLoading: true,
      clearError: true,
    );

    try {
      final results = await _youTubeService.search(cleanQuery);
      state = state.copyWith(
        results: results,
        isLoading: false,
        clearError: true,
      );
    } on AppException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Terjadi kesalahan saat mencari lagu: $e',
      );
    }
  }

  void clear() {
    state = const SearchState();
  }
}
