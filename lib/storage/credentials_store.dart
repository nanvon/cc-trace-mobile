import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/token_bundle.dart';
import '../domain/quota_models.dart';

abstract interface class CredentialsStore {
  Future<TokenBundle?> read(ProviderId provider);
  Future<void> write(TokenBundle bundle);
  Future<bool> replaceIfCurrent({
    required TokenBundle expected,
    required TokenBundle replacement,
  });
  Future<void> delete(ProviderId provider);
  Future<void> clear();
}

class SecureCredentialsStore implements CredentialsStore {
  SecureCredentialsStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(storageNamespace: 'cc_trace_mobile'),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
              synchronizable: false,
            ),
          );

  static const _prefix = 'credentials.v1.';
  final FlutterSecureStorage _storage;
  final _CredentialMutationQueue _mutations = _CredentialMutationQueue();

  String _key(ProviderId provider) => '$_prefix${provider.storageKey}';

  @override
  Future<TokenBundle?> read(ProviderId provider) => _readUnlocked(provider);

  Future<TokenBundle?> _readUnlocked(ProviderId provider) async {
    final raw = await _storage.read(key: _key(provider));
    if (raw == null) {
      return null;
    }
    try {
      final value = jsonDecode(raw);
      return value is Map<String, Object?> ? TokenBundle.fromJson(value) : null;
    } on Object {
      await _storage.delete(key: _key(provider));
      return null;
    }
  }

  @override
  Future<void> write(TokenBundle bundle) {
    return _mutations.run(
      bundle.provider,
      () => _storage.write(
        key: _key(bundle.provider),
        value: jsonEncode(bundle.toJson()),
      ),
    );
  }

  @override
  Future<bool> replaceIfCurrent({
    required TokenBundle expected,
    required TokenBundle replacement,
  }) {
    assert(expected.provider == replacement.provider);
    return _mutations.run(expected.provider, () async {
      final current = await _readUnlocked(expected.provider);
      if (current == null || !current.hasSameAuthMaterialAs(expected)) {
        return false;
      }
      await _storage.write(
        key: _key(replacement.provider),
        value: jsonEncode(replacement.toJson()),
      );
      return true;
    });
  }

  @override
  Future<void> delete(ProviderId provider) {
    return _mutations.run(provider, () => _storage.delete(key: _key(provider)));
  }

  @override
  Future<void> clear() async {
    for (final provider in ProviderId.values) {
      await delete(provider);
    }
  }
}

class MemoryCredentialsStore implements CredentialsStore {
  final Map<ProviderId, TokenBundle> _values = {};
  final _CredentialMutationQueue _mutations = _CredentialMutationQueue();

  @override
  Future<void> clear() async {
    for (final provider in ProviderId.values) {
      await delete(provider);
    }
  }

  @override
  Future<void> delete(ProviderId provider) {
    return _mutations.run(provider, () async {
      _values.remove(provider);
    });
  }

  @override
  Future<TokenBundle?> read(ProviderId provider) async => _values[provider];

  @override
  Future<void> write(TokenBundle bundle) {
    return _mutations.run(bundle.provider, () async {
      _values[bundle.provider] = bundle;
    });
  }

  @override
  Future<bool> replaceIfCurrent({
    required TokenBundle expected,
    required TokenBundle replacement,
  }) {
    assert(expected.provider == replacement.provider);
    return _mutations.run(expected.provider, () async {
      final current = _values[expected.provider];
      if (current == null || !current.hasSameAuthMaterialAs(expected)) {
        return false;
      }
      _values[replacement.provider] = replacement;
      return true;
    });
  }
}

class _CredentialMutationQueue {
  final Map<ProviderId, Future<void>> _tails = {};

  Future<T> run<T>(ProviderId provider, Future<T> Function() operation) async {
    final previous = _tails[provider];
    final completed = Completer<void>();
    _tails[provider] = completed.future;
    if (previous != null) {
      await previous;
    }
    try {
      return await operation();
    } finally {
      completed.complete();
      if (identical(_tails[provider], completed.future)) {
        _tails.remove(provider);
      }
    }
  }
}
