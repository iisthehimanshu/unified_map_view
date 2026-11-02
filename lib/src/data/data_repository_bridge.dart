import 'package:data_repository/data_repository.dart';

import '../config.dart';

/// Data_Repository, which sends this package's venue requests and keeps its
/// venue cache.
///
/// A host such as navigation_sdk sets it up with its own config, the same
/// server and key it hands this package, plus details this package doesn't
/// know (the device sent with `patch/get`). So when it is already set up, only
/// the server and key this package was explicitly given are applied, and
/// never this package's built-in fallback key. A standalone app gets this
/// package's config, kept in step with the server: `initialize` sets it up
/// before the controller is given its `url`, and the built-in key is chosen
/// per server, so the key must follow the server or the new one answers 403.
Future<DataRepository> dataRepository() async {
  if (!DataRepository.isReady) {
    _setUpHere = true;
    return DataRepository.init(
        DataConfig(baseUrl: AppConfig.baseUrl, apiKey: AppConfig.apiKey));
  }
  final repo = DataRepository.instance;
  final current = repo.config;
  final given = _setUpHere
      ? current.copyWith(baseUrl: AppConfig.baseUrl, apiKey: AppConfig.apiKey)
      : current.copyWith(baseUrl: AppConfig.url, apiKey: AppConfig.hostApiKey);
  if (given != current) repo.configure(given);
  return repo;
}

/// Whether this package set Data_Repository up, so its config is ours to keep.
bool _setUpHere = false;
