import 'package:hive/hive.dart';

part 'settings.g.dart';

@HiveType(typeId: 4)
class Settings {
  @HiveField(0)
  final int cacheLimitMB;

  const Settings({
    this.cacheLimitMB = 500,
  });

  Settings copyWith({
    int? cacheLimitMB,
  }) {
    return Settings(
      cacheLimitMB: cacheLimitMB ?? this.cacheLimitMB,
    );
  }
}
