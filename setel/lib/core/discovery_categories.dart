export 'discovery_config.dart';

import 'discovery_config.dart';

final List<DiscoveryCategory> indoCategories =
    DiscoveryConfigService.defaultHardcodedCategories
        .where((c) => c.group == 'INDO')
        .toList();

final List<DiscoveryCategory> mancaCategories =
    DiscoveryConfigService.defaultHardcodedCategories
        .where((c) => c.group == 'MANCA')
        .toList();
