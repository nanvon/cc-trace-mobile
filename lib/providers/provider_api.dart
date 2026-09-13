// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../auth/oauth_config.dart';
import '../auth/token_bundle.dart';
import '../diagnostics/app_diagnostics.dart';
import '../domain/quota_models.dart';
import '../network/abortable_http.dart';
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
    this.credits,
    this.spend,
    this.failure,
    this.retryAfter,
  });

  factory ProviderFetchResult.success({
    required ProviderId provider,
    required QuotaSnapshot snapshot,
    required ProviderIdentity identity,
    ResetCreditsSnapshot? resetCredits,
    CodexCredits? credits,
    ClaudeSpend? spend,
  }) {
    return ProviderFetchResult._(
      provider: provider,
      snapshot: snapshot,
      identity: identity,
      resetCredits: resetCredits,
      credits: credits,
      spend: spend,
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
  final CodexCredits? credits;
  final ClaudeSpend? spend;
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
    AppDiagnostics? diagnostics,
  }) : _credentials = credentials,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _now = now ?? DateTime.now,
       _diagnostics = diagnostics ?? AppDiagnostics.instance;

  final CredentialsStore _credentials;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final AppDiagnostics _diagnostics;
  final Map<ProviderId, _TokenRefresh> _refreshingTokens = {};

  @override
  Future<ProviderFetchResult> fetch(ProviderId provider) async {
    late final TokenBundle? stored;
    try {
      stored = await _credentials.read(provider);
    } on Object catch (error) {
      _diagnostics.record('credentials.readFailed', {
        'provider': provider.name,
        'type': error.runtimeType.toString(),
      });
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
        credits: parsed.credits,
      );
    }

    final results = await Future.wait<Object>([
      _requestUsage(provider, token),
      _withClaudeProfile(token),
    ]);
    final parsed = results[0] as ParsedUsage;
    final identifiedToken = results[1] as TokenBundle;
    return ProviderFetchResult.success(
      provider: provider,
      snapshot: parsed.snapshot,
      identity: _identity(identifiedToken, parsed.identity),
      spend: parsed.spend,
    );
  }

  ProviderIdentity _identity(
    TokenBundle token,
    ProviderIdentity? responseIdentity,
  ) {
    return ProviderIdentity(
      accountHint: token.accountHint,
      // Codex 的套餐名来自每次 usage 响应；Claude 的来自随凭据留存的 profile 结果。
      plan: responseIdentity?.plan ?? token.plan,
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
      final request = http.Request('POST', Uri.parse(config.tokenEndpoint))
        ..headers.addAll(const {'Accept': 'application/json'});
      if (token.provider == ProviderId.codex) {
        request.bodyFields = {
          'grant_type': 'refresh_token',
          'refresh_token': token.refreshToken,
          'client_id': config.clientId,
          'scope': 'openid profile email',
        };
      } else {
        request.bodyFields = {
          'grant_type': 'refresh_token',
          'refresh_token': token.refreshToken,
          'client_id': config.clientId,
        };
      }
      response = await sendWithTimeout(_client, request);
    } on TimeoutException {
      _recordUnreachable('token', 'timeout');
      throw const _RequestFailure(ProviderFetchFailureKind.offline);
    } on SocketException {
      _recordUnreachable('token', 'socket');
      throw const _RequestFailure(ProviderFetchFailureKind.offline);
    } on TlsException {
      _recordUnreachable('token', 'tls');
      throw const _RequestFailure(ProviderFetchFailureKind.offline);
    } on http.ClientException {
      _recordUnreachable('token', 'client');
      throw const _RequestFailure(ProviderFetchFailureKind.offline);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final failure = _tokenEndpointFailure(response);
      _diagnostics.record('token.refreshFailed', {
        'provider': token.provider.name,
        'status': response.statusCode,
        'kind': failure.kind.name,
      });
      throw failure;
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
            emailFromPayload(accessPayload) ??
            emailFromPayload(idPayload) ??
            token.accountHint,
        accountFingerprint:
            identityFingerprintFromPayloads(accessPayload, idPayload) ??
            token.accountFingerprint,
        // 刷新响应不含套餐名，沿用已取得的，不要在刷新时丢掉它。
        plan: token.plan,
      );
      final stored = await _credentials.replaceIfCurrent(
        expected: token,
        replacement: refreshed,
      );
      if (!stored) {
        throw const _RequestFailure(ProviderFetchFailureKind.superseded);
      }
      _diagnostics.record('token.refreshed', {
        'provider': token.provider.name,
        'expiresIn': refreshed.expiresAt?.difference(_now()).inMinutes,
      });
      return refreshed;
    } on _RequestFailure {
      rethrow;
    } on Object {
      _diagnostics.record('token.refreshUnreadable', {
        'provider': token.provider.name,
      });
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
    final response = await _get(
      Uri.parse(config.usageEndpoint),
      headers,
      'usage',
    );
    final body = utf8.decode(response.bodyBytes);
    final capturedAt = _now();
    try {
      return switch (provider) {
        ProviderId.codex => parseCodexUsage(body, capturedAt),
        ProviderId.claude => parseClaudeUsage(body, capturedAt),
      };
    } on Object {
      _diagnostics.record('parse.failed', {
        'endpoint': 'usage',
        'provider': provider.name,
      });
      throw const _RequestFailure(ProviderFetchFailureKind.protocol);
    }
  }

  Future<TokenBundle> _withClaudeProfile(TokenBundle token) async {
    // 套餐名也只有这个接口给，所以它未取得时同样要再请求一次。
    if (token.accountHint != null &&
        token.accountFingerprint != null &&
        token.plan != null) {
      return token;
    }

    try {
      final profile = await _requestClaudeProfile(token);
      final identified = token.copyWith(
        accountHint: profile.email,
        accountFingerprint: identityFingerprint(profile.accountUuid),
        plan: profile.plan,
      );
      final stored = await _credentials.replaceIfCurrent(
        expected: token,
        replacement: identified,
      );
      if (!stored) {
        throw const _RequestFailure(ProviderFetchFailureKind.superseded);
      }
      return identified;
    } on _RequestFailure catch (failure) {
      if (failure.kind == ProviderFetchFailureKind.superseded) {
        rethrow;
      }
      return token;
    } on Object {
      return token;
    }
  }

  Future<_ClaudeProfile> _requestClaudeProfile(TokenBundle token) async {
    final response = await _get(Uri.parse(claudeProfileEndpoint), {
      'Accept': 'application/json',
      'Authorization': 'Bearer ${token.accessToken}',
      'Content-Type': 'application/json',
    }, 'profile');
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException();
    }
    final root = decoded.cast<String, Object?>();
    final rawAccount = root['account'];
    if (rawAccount is! Map) {
      throw const FormatException();
    }
    final account = rawAccount.cast<String, Object?>();
    final accountUuid = _nonEmptyText(account['uuid']);
    final email = _nonEmptyText(account['email']);
    if (accountUuid == null || email == null || !email.contains('@')) {
      throw const FormatException();
    }
    final rawOrganization = root['organization'];
    final organization = rawOrganization is Map
        ? rawOrganization.cast<String, Object?>()
        : const <String, Object?>{};
    return _ClaudeProfile(
      accountUuid: accountUuid,
      email: email,
      plan: _claudePlan(_nonEmptyText(organization['organization_type'])),
    );
  }

  /// `organization_type` 到套餐名的映射，与 Claude Code 2.1.212 内置的表一致。
  ///
  /// 表外的取值一律返回 `null`：宁可不显示套餐，也不把内部枚举名直接摆到界面上。
  /// 同一对象上的 `rate_limit_tier` 不是套餐名（形如 `default_claude_max_20x`），
  /// 官方客户端把它单独存成 `rateLimitTier`，这里不拿它兜底。
  String? _claudePlan(String? organizationType) {
    return switch (organizationType) {
      'claude_max' => 'Max',
      'claude_pro' => 'Pro',
      'claude_team' => 'Team',
      'claude_enterprise' => 'Enterprise',
      _ => null,
    };
  }

  Future<ResetCreditsSnapshot> _requestResetCredits(TokenBundle token) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer ${token.accessToken}',
      'User-Agent': 'codex-cli',
      if (token.accountId != null) 'ChatGPT-Account-Id': token.accountId!,
    };
    final response = await _get(
      Uri.parse(resetCreditsEndpoint),
      headers,
      'resetCredits',
    );
    try {
      return parseResetCredits(utf8.decode(response.bodyBytes));
    } on Object {
      _diagnostics.record('parse.failed', {'endpoint': 'resetCredits'});
      throw const _RequestFailure(ProviderFetchFailureKind.protocol);
    }
  }

  /// [endpoint] 只是给诊断日志用的短名（`usage` / `profile` / `resetCredits`），
  /// 不写完整 URL：完整 URL 里可能带账号相关的查询参数。
  Future<http.Response> _get(
    Uri uri,
    Map<String, String> headers,
    String endpoint,
  ) async {
    late final http.Response response;
    try {
      final request = http.Request('GET', uri)..headers.addAll(headers);
      response = await sendWithTimeout(_client, request);
    } on TimeoutException {
      _recordUnreachable(endpoint, 'timeout');
      throw const _RequestFailure(ProviderFetchFailureKind.offline);
    } on SocketException {
      _recordUnreachable(endpoint, 'socket');
      throw const _RequestFailure(ProviderFetchFailureKind.offline);
    } on TlsException {
      // HandshakeException / CertificateException 都在这里。`package:http` 的
      // IOClient 只把 SocketException 与 HttpException 包成 ClientException，
      // TLS 失败会原样抛出；不接住它，代理证书问题就会被当成接口变更。
      _recordUnreachable(endpoint, 'tls');
      throw const _RequestFailure(ProviderFetchFailureKind.offline);
    } on http.ClientException {
      _recordUnreachable(endpoint, 'client');
      throw const _RequestFailure(ProviderFetchFailureKind.offline);
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // 强制门户和拦截型代理也会用 200 返回一张网页。那不是 Provider 的回答，
      // 让它走到解析失败会把链路问题说成「响应格式变了」。
      if (_declaresNonJson(response)) {
        _diagnostics.record('http.notJson', {
          'endpoint': endpoint,
          'status': response.statusCode,
        });
        throw const _RequestFailure(ProviderFetchFailureKind.offline);
      }
      return response;
    }
    _diagnostics.record('http.status', {
      'endpoint': endpoint,
      'status': response.statusCode,
      'json': _looksLikeJson(response),
    });
    throw _httpFailure(response);
  }

  void _recordUnreachable(String endpoint, String reason) {
    _diagnostics.record('http.unreachable', {
      'endpoint': endpoint,
      'reason': reason,
    });
  }

  _RequestFailure _httpFailure(http.Response response) {
    // 代理要求认证：请求没到 Provider，和凭据无关。
    if (response.statusCode == 407) {
      return const _RequestFailure(ProviderFetchFailureKind.offline);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      // 代理、网关、强制门户同样用 401/403 拦截，但它们返回网页而不是 JSON。
      // 只有 Provider 自己的 JSON 回答才说明凭据真的不能用了；把拦截页当成
      // 凭据失效，会让用户以为要重新登录，实际只是网络不通。
      return _looksLikeJson(response)
          ? const _RequestFailure(ProviderFetchFailureKind.credentials)
          : const _RequestFailure(ProviderFetchFailureKind.offline);
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

  /// token endpoint 的失败判定，比资源端点更严：凭据失效必须由响应体自己说明。
  ///
  /// 按 RFC 6749 §5.2，refresh_token 失效返回的是 `400` 加 `{"error":
  /// "invalid_grant"}`。仅凭状态码判断会把代理和网关的 400/401/403 也算成失效，
  /// 而凭据失效在 [AppController] 里会阻断自动刷新，代价比多重试一次高得多。
  _RequestFailure _tokenEndpointFailure(http.Response response) {
    if (response.statusCode == 407) {
      return const _RequestFailure(ProviderFetchFailureKind.offline);
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
    // 不是 JSON 就不是 token endpoint 的回答，是链路上的东西替它答的。
    if (!_looksLikeJson(response)) {
      return const _RequestFailure(ProviderFetchFailureKind.offline);
    }
    if (_isCredentialOAuthError(response)) {
      return const _RequestFailure(ProviderFetchFailureKind.credentials);
    }
    return const _RequestFailure(ProviderFetchFailureKind.protocol);
  }

  /// RFC 6749 §5.2 里表示「这份凭据不能再用」的几个 `error` 取值。
  ///
  /// `invalid_request` 不在其中：那是请求本身拼错了，重新登录解决不了。
  static const _credentialOAuthErrors = {
    'invalid_grant',
    'invalid_client',
    'unauthorized_client',
  };

  bool _isCredentialOAuthError(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map &&
          _credentialOAuthErrors.contains(decoded['error']);
    } on Object {
      return false;
    }
  }

  /// 这份响应像不像 Provider 自己给的 JSON。
  ///
  /// `content-type` 在就以它为准——拦截页会老实声明 `text/html`。头缺失时退而
  /// 看响应体首字符：不是每个服务器都带这个头，缺头不该直接当成拦截。
  bool _looksLikeJson(http.Response response) {
    final type = response.headers['content-type']?.toLowerCase();
    if (type != null) {
      return type.contains('json');
    }
    final body = utf8
        .decode(response.bodyBytes, allowMalformed: true)
        .trimLeft();
    return body.startsWith('{') || body.startsWith('[');
  }

  /// `content-type` 明确声明了别的东西。头缺失同样返回 false，走原有解析路径，
  /// 免得把只是没带响应头的正常回答误判成拦截页。
  bool _declaresNonJson(http.Response response) {
    final type = response.headers['content-type'];
    return type != null && !type.toLowerCase().contains('json');
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

  String? _nonEmptyText(Object? value) {
    if (value is! String) {
      return null;
    }
    final text = value.trim();
    return text.isEmpty ? null : text;
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

class _ClaudeProfile {
  const _ClaudeProfile({
    required this.accountUuid,
    required this.email,
    this.plan,
  });

  final String accountUuid;
  final String email;
  final String? plan;
}
