// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../auth/oauth_config.dart';
import '../auth/token_bundle.dart';
import '../domain/quota_models.dart';
import '../storage/credentials_store.dart';
import 'usage_parsers.dart';

enum ProviderFetchFailureKind {
  noCredentials,
  superseded,
  credentials,
  rateLimited,
  offline,
  protocol,
}

class ProviderFetchResult {
  const ProviderFetchResult._({
    required this.provider,
    this.snapshot,
    this.identity,
    this.resetCredits,
    this.failure,
    this.retryAfter,
  });

  factory ProviderFetchResult.success({
    required ProviderId provider,
    required QuotaSnapshot snapshot,
    required ProviderIdentity identity,
    ResetCreditsSnapshot? resetCredits,
  }) {
    return ProviderFetchResult._(
      provider: provider,
      snapshot: snapshot,
      identity: identity,
      resetCredits: resetCredits,
    );
  }

  factory ProviderFetchResult.failure({
    required ProviderId provider,
    required ProviderFetchFailureKind failure,
    Duration? retryAfter,
  }) {
    return ProviderFetchResult._(
      provider: provider,
      failure: failure,
      retryAfter: retryAfter,
    );
  }

  final ProviderId provider;
  final QuotaSnapshot? snapshot;
  final ProviderIdentity? identity;
  final ResetCreditsSnapshot? resetCredits;
  final ProviderFetchFailureKind? failure;
  final Duration? retryAfter;

  bool get isSuccess => snapshot != null;
}

abstract interface class ProviderGateway {
  Future<ProviderFetchResult> fetch(ProviderId provider);
}

class ProviderApi implements ProviderGateway {
  ProviderApi({
    required CredentialsStore credentials,
    http.Client? client,
    DateTime Function()? now,
  }) : _credentials = credentials,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _now = now ?? DateTime.now;

  final CredentialsStore _credentials;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final Map<ProviderId, _TokenRefresh> _refreshingTokens = {};

  @override
  Future<ProviderFetchResult> fetch(ProviderId provider) async {
    late final TokenBundle? stored;
    try {
      stored = await _credentials.read(provider);
    } on Object {
      return ProviderFetchResult.failure(
        provider: provider,
        failure: ProviderFetchFailureKind.protocol,
      );
    }
    if (stored == null) {
      return ProviderFetchResult.failure(
        provider: provider,
        failure: ProviderFetchFailureKind.noCredentials,
      );
    }

    late final TokenBundle token;
    try {
      token = await _usableToken(stored);
    } on _RequestFailure catch (failure) {
      return _failureResult(provider, failure);
    } on Object {
      return ProviderFetchResult.failure(
        provider: provider,
        failure: ProviderFetchFailureKind.protocol,
      );
    }

    try {
      return await _fetchWithToken(provider, token);
    } on _RequestFailure catch (failure) {
      if (failure.kind == ProviderFetchFailureKind.credentials &&
          identical(token, stored)) {
        try {
          final refreshed = await _refreshToken(token);
          return await _fetchWithToken(provider, refreshed);
        } on _RequestFailure catch (refreshFailure) {
          return _failureResult(provider, refreshFailure);
        } on Object {
          return ProviderFetchResult.failure(
            provider: provider,
            failure: ProviderFetchFailureKind.protocol,
          );
        }
      }
      return _failureResult(provider, failure);
    } on Object {
      return ProviderFetchResult.failure(
        provider: provider,
        failure: ProviderFetchFailureKind.protocol,
      );
    }
  }

  Future<ProviderFetchResult> _fetchWithToken(
    ProviderId provider,
    TokenBundle token,
  ) async {
    if (provider == ProviderId.codex) {
      final usage = _requestUsage(provider, token);
      final credits = _requestResetCredits(
        token,
      ).then<ResetCreditsSnapshot?>((value) => value, onError: (_) => null);
      final parsed = await usage;
      final resetCredits = await credits;
      return ProviderFetchResult.success(
        provider: provider,
        snapshot: parsed.snapshot,
        identity: _identity(token, parsed.identity),
        resetCredits: resetCredits,
      );
    }

    final parsed = await _requestUsage(provider, token);
    return ProviderFetchResult.success(
      provider: provider,
      snapshot: parsed.snapshot,
      identity: _identity(token, parsed.identity),
    );
  }

  ProviderIdentity _identity(
    TokenBundle token,
    ProviderIdentity? responseIdentity,
  ) {
    return ProviderIdentity(
      accountHint: token.accountHint,
      plan: responseIdentity?.plan,
      identityKey: token.identityKey,
    );
  }

  Future<TokenBundle> _usableToken(TokenBundle token) {
    final skew = token.provider == ProviderId.codex
        ? const Duration(minutes: 5)
        : const Duration(seconds: 30);
    if (!token.expiresWithin(_now(), skew)) {
      return Future.value(token);
    }
    final active = _refreshingTokens[token.provider];
    if (active != null && active.expected.hasSameAuthMaterialAs(token)) {
      return active.future;
    }

    late final _TokenRefresh refresh;
    final future = () async {
      try {
        return await _refreshToken(token);
      } finally {
        if (identical(_refreshingTokens[token.provider], refresh)) {
          _refreshingTokens.remove(token.provider);
        }
      }
    }();
    refresh = _TokenRefresh(expected: token, future: future);
    _refreshingTokens[token.provider] = refresh;
    return future;
  }

  Future<TokenBundle> _refreshToken(TokenBundle token) async {
    final config = providerConfigs[token.provider]!;
    late final http.Response response;
    try {
      response = switch (token.provider) {
        ProviderId.codex =>
          await _client
              .post(
                Uri.parse(config.tokenEndpoint),
                headers: const {'Accept': 'application/json'},
                body: {
                  'grant_type': 'refresh_token',
                  'refresh_token': token.refreshToken,
                  'client_id': config.clientId,
                  'scope': 'openid profile email',
                },
              )
              .timeout(const Duration(seconds: 15)),
        ProviderId.claude =>
          await _client
              .post(
                Uri.parse(config.tokenEndpoint),
                headers: const {'Accept': 'application/json'},
                body: {
                  'grant_type': 'refresh_token',
                  'refresh_token': token.refreshToken,
                  'client_id': config.clientId,
                },
              )
              .timeout(const Duration(seconds: 15)),
      };
    } on TimeoutException {
      throw const _RequestFailure(ProviderFetchFailureKind.offline);
    } on SocketException {
      throw const _RequestFailure(ProviderFetchFailureKind.offline);
    } on http.ClientException {
      throw const _RequestFailure(ProviderFetchFailureKind.offline);
    }

    if (response.statusCode == 400 ||
        response.statusCode == 401 ||
        response.statusCode == 403) {
      throw const _RequestFailure(ProviderFetchFailureKind.credentials);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpFailure(response);
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const FormatException();
      }
      final body = decoded.cast<String, Object?>();
      final accessToken = _token(body['access_token']);
      if (accessToken == null) {
        throw const FormatException();
      }
      final idToken = _token(body['id_token']) ?? token.idToken;
      final accessPayload = decodeJwtPayload(accessToken);
      final idPayload = decodeJwtPayload(idToken);
      final expiresIn = body['expires_in'];
      final now = _now();
      final refreshed = TokenBundle(
        provider: token.provider,
        accessToken: accessToken,
        refreshToken: _token(body['refresh_token']) ?? token.refreshToken,
        idToken: idToken,
        obtainedAt: now,
        expiresAt:
            jwtExpiry(accessPayload) ??
            (expiresIn is num
                ? now.add(Duration(seconds: expiresIn.toInt()))
                : null),
        accountId: token.provider == ProviderId.codex
            ? jwtStringClaim(accessPayload, 'chatgpt_account_id') ??
                  jwtStringClaim(idPayload, 'chatgpt_account_id') ??
                  token.accountId
            : token.accountId,
        accountHint:
            maskedEmailFromPayload(accessPayload) ??
            maskedEmailFromPayload(idPayload) ??
            token.accountHint,
        accountFingerprint:
            identityFingerprintFromPayloads(accessPayload, idPayload) ??
            token.accountFingerprint,
      );
      final stored = await _credentials.replaceIfCurrent(
        expected: token,
        replacement: refreshed,
      );
      if (!stored) {
        throw const _RequestFailure(ProviderFetchFailureKind.superseded);
      }
      return refreshed;
    } on _RequestFailure {
      rethrow;
    } on Object {
      throw const _RequestFailure(ProviderFetchFailureKind.protocol);
    }
  }

  Future<ParsedUsage> _requestUsage(
    ProviderId provider,
    TokenBundle token,
  ) async {
    final config = providerConfigs[provider]!;
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer ${token.accessToken}',
      if (provider == ProviderId.codex) 'User-Agent': 'codex-cli',
      if (provider == ProviderId.codex && token.accountId != null)
        'ChatGPT-Account-Id': token.accountId!,
      if (provider == ProviderId.claude) 'anthropic-beta': 'oauth-2025-04-20',
    };
    final response = await _get(Uri.parse(config.usageEndpoint), headers);
    final body = utf8.decode(response.bodyBytes);
    final capturedAt = _now();
    try {
      return switch (provider) {
        ProviderId.codex => parseCodexUsage(body, capturedAt),
        ProviderId.claude => parseClaudeUsage(body, capturedAt),
      };
    } on Object {
      throw const _RequestFailure(ProviderFetchFailureKind.protocol);
    }
  }

  Future<ResetCreditsSnapshot> _requestResetCredits(TokenBundle token) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer ${token.accessToken}',
      'User-Agent': 'codex-cli',
      if (token.accountId != null) 'ChatGPT-Account-Id': token.accountId!,
    };
    final response = await _get(Uri.parse(resetCreditsEndpoint), headers);
    try {
      return parseResetCredits(utf8.decode(response.bodyBytes));
    } on Object {
      throw const _RequestFailure(ProviderFetchFailureKind.protocol);
    }
  }

  Future<http.Response> _get(Uri uri, Map<String, String> headers) async {
    late final http.Response response;
    try {
      response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const _RequestFailure(ProviderFetchFailureKind.offline);
    } on SocketException {
      throw const _RequestFailure(ProviderFetchFailureKind.offline);
    } on http.ClientException {
      throw const _RequestFailure(ProviderFetchFailureKind.offline);
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw _httpFailure(response);
  }

  _RequestFailure _httpFailure(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      return const _RequestFailure(ProviderFetchFailureKind.credentials);
    }
    if (response.statusCode == 429) {
      return _RequestFailure(
        ProviderFetchFailureKind.rateLimited,
        retryAfter: _parseRetryAfter(response.headers['retry-after']),
      );
    }
    if (response.statusCode >= 500) {
      return const _RequestFailure(ProviderFetchFailureKind.offline);
    }
    return const _RequestFailure(ProviderFetchFailureKind.protocol);
  }

  Duration? _parseRetryAfter(String? value) {
    if (value == null) {
      return null;
    }
    final seconds = int.tryParse(value);
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds);
    }
    try {
      final date = HttpDate.parse(value);
      final duration = date.difference(_now());
      return duration.isNegative ? Duration.zero : duration;
    } on FormatException {
      return null;
    }
  }

  ProviderFetchResult _failureResult(
    ProviderId provider,
    _RequestFailure failure,
  ) {
    return ProviderFetchResult.failure(
      provider: provider,
      failure: failure.kind,
      retryAfter: failure.retryAfter,
    );
  }

  String? _token(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class _RequestFailure implements Exception {
  const _RequestFailure(this.kind, {this.retryAfter});

  final ProviderFetchFailureKind kind;
  final Duration? retryAfter;

  @override
  String toString() => '_RequestFailure($kind, <response redacted>)';
}

class _TokenRefresh {
  const _TokenRefresh({required this.expected, required this.future});

  final TokenBundle expected;
  final Future<TokenBundle> future;
}
