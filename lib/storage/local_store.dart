import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_settings.dart';
import '../domain/quota_models.dart';
import 'credentials_store.dart';

abstract interface class LocalStore {
  Future<AppSettings> readSettings();
  Future<void> writeSettings(AppSettings settings);
  Future<List<ProviderViewState>> readQuotaCache();
  Future<void> writeQuotaCache(Iterable<ProviderViewState> providers);
  Future<void> removeProviderCache(ProviderId provider);
  Future<void> prepareInstall(CredentialsStore credentials);
}

class SharedPreferencesLocalStore implements LocalStore {
  SharedPreferencesLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _settingsKey = 'settings.v1';
  static const _quotaCacheKey = 'quotaCache.v1';
  static const _installMarkerKey = 'installMarker.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<void> prepareInstall(CredentialsStore credentials) async {
    final installed = await _preferences.getBool(_installMarkerKey) ?? false;
    if (!installed) {
      await credentials.clear();
      await _preferences.remove(_quotaCacheKey);
      await _preferences.setBool(_installMarkerKey, true);
    }
  }

  @override
  Future<AppSettings> readSettings() async {
    final raw = await _preferences.getString(_settingsKey);
    if (raw == null) {
      return const AppSettings();
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?>
          ? AppSettings.fromJson(decoded)
          : const AppSettings();
    } on Object {
      return const AppSettings();
    }
  }

  @override
  Future<void> writeSettings(AppSettings settings) {
    return _preferences.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  @override
  Future<List<ProviderViewState>> readQuotaCache() async {
    final raw = await _preferences.getString(_quotaCacheKey);
    if (raw == null) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?> ||
          decoded['schemaVersion'] != 1 ||
          decoded['providers'] is! List<Object?>) {
        await _preferences.remove(_quotaCacheKey);
        return [];
      }
      return (decoded['providers']! as List<Object?>)
          .whereType<Map<String, Object?>>()
          .map(ProviderViewState.fromCacheJson)
          .where((state) => state.hasSnapshot)
          .toList(growable: false);
    } on Object {
      await _preferences.remove(_quotaCacheKey);
      return [];
    }
  }

  @override
  Future<void> writeQuotaCache(Iterable<ProviderViewState> providers) {
    final cacheable = providers.where((provider) => provider.hasSnapshot);
    return _preferences.setString(
      _quotaCacheKey,
      jsonEncode({
        'schemaVersion': 1,
        'providers': cacheable
            .map((provider) => provider.toCacheJson())
            .toList(),
      }),
    );
  }

  @override
  Future<void> removeProviderCache(ProviderId provider) async {
    final cached = await readQuotaCache();
    await writeQuotaCache(
      cached.where((candidate) => candidate.provider != provider),
    );
  }
}

class MemoryLocalStore implements LocalStore {
  AppSettings settings = const AppSettings();
  final Map<ProviderId, ProviderViewState> cached = {};
  bool installed = false;

  @override
  Future<void> prepareInstall(CredentialsStore credentials) async {
    if (!installed) {
      await credentials.clear();
      cached.clear();
      installed = true;
    }
  }

  @override
  Future<List<ProviderViewState>> readQuotaCache() async =>
      cached.values.toList(growable: false);

  @override
  Future<AppSettings> readSettings() async => settings;

  @override
  Future<void> removeProviderCache(ProviderId provider) async {
    cached.remove(provider);
  }

  @override
  Future<void> writeQuotaCache(Iterable<ProviderViewState> providers) async {
    cached
      ..clear()
      ..addEntries(
        providers
            .where((provider) => provider.hasSnapshot)
            .map((provider) => MapEntry(provider.provider, provider)),
      );
  }

  @override
  Future<void> writeSettings(AppSettings value) async {
    settings = value;
  }
}
