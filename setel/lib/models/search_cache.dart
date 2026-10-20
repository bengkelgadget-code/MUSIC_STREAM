import 'package:hive/hive.dart';

part 'search_cache.g.dart';

@HiveType(typeId: 3)
class SearchCache {
  @HiveField(0)
  final String query;

  @HiveField(1)
  final List<String> videoIds;

  @HiveField(2)
  final DateTime cachedAt;

  const SearchCache({
    required this.query,
    required this.videoIds,
    required this.cachedAt,
  });

  bool isExpired({Duration ttl = const Duration(hours: 24)}) {
    return DateTime.now().difference(cachedAt) > ttl;
  }
}
