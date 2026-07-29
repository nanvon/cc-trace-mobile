// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/quota_models.dart';
import '../q3/browser_bridge.dart';
import 'oauth_callback_server.dart';
import 'oauth_config.dart';
import 'oauth_material.dart';
import 'token_bundle.dart';

enum OAuthFailureKind {
  cancelled,
  timeout,
  portUnavailable,
  browserUnavailable,
  tokenExchange,
  invalidResponse,
  secureStorage,
}

class OAuthFailure implements Exception {
  const OAuthFailure(this.kind);

  final OAuthFailureKind kind;

  @override
  String toString() => 'OAuthFailure($kind, <details redacted>)';
}

typedef BrowserLauncherFactory = BrowserLauncher Function();

abstract interface class OAuthGateway {
  Future<TokenBundle> signIn(ProviderId provider);
  void dispose();
}

class OAuthCoordinator implements OAuthGateway {
  OAuthCoordinator({
    http.Client? client,
    BrowserLauncherFactory? browserFactory,
    Map<ProviderId, OAuthConfig>? configs,
    this.timeout = const Duration(minutes: 5),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _browserFactory = browserFactory ?? OAuthBrowserBridge.new,
       _configs = configs ?? providerConfigs;

  final http.Client _client;
  final bool _ownsClient;
  final BrowserLauncherFactory _browserFactory;
  final Map<ProviderId, OAuthConfig> _configs;
  final Duration timeout;

  @override
  Future<TokenBundle> signIn(ProviderId provider) async {
    final config = _configs[provider]!;
    final material = createOAuthMaterial();
    OAuthCallbackServer? server;
    BrowserLauncher? browser;
    StreamSubscription<OAuthCallbackEvent>? callbackSubscription;
    StreamSubscription<OAuthBrowserEvent>? browserSubscription;
    Timer? timeoutTimer;
    final result = Completer<String>();

    try {
      server = await OAuthCallbackServer.bind(
        config: config,
        expectedState: material.state,
      );
      browser = _browserFactory();
      callbackSubscription = server.events.listen((event) {
        if (result.isCompleted) {
          return;
        }
        switch (event.kind) {
          case OAuthCallbackKind.accepted:
            result.complete(event.authorizationCode!);
          case OAuthCallbackKind.providerCancelled:
            result.completeError(
              const OAuthFailure(OAuthFailureKind.cancelled),
            );
          case OAuthCallbackKind.serverError:
            result.completeError(
              const OAuthFailure(OAuthFailureKind.invalidResponse),
            );
          case OAuthCallbackKind.invalid:
            break;
        }
      });
      browserSubscription = browser.events.listen((event) {
        if (result.isCompleted) {
          return;
        }
        switch (event.type) {
          case OAuthBrowserEventType.cancelled:
            result.completeError(
              const OAuthFailure(OAuthFailureKind.cancelled),
            );
          case OAuthBrowserEventType.returned:
            // Android Custom Tabs may resume this Activity while an external
            // resolver is still completing the localhost navigation. A resume
            // is not evidence of cancellation, so keep the listener alive.
            break;
          case OAuthBrowserEventType.failed:
            result.completeError(
              const OAuthFailure(OAuthFailureKind.browserUnavailable),
            );
        }
      });
      timeoutTimer = Timer(timeout, () {
        if (!result.isCompleted) {
          result.completeError(const OAuthFailure(OAuthFailureKind.timeout));
        }
      });

      await browser.open(
        config.authorizeUri(
          port: server.port,
          state: material.state,
          challenge: material.challenge,
        ),
      );
      final code = await result.future;
      await _ignoreFailure(browser.close);
      final bundle = await _exchangeCode(
        config: config,
        material: material,
        redirectUri: config.redirectUri(server.port),
        code: code,
      );
      return bundle;
    } on SocketException {
      throw const OAuthFailure(OAuthFailureKind.portUnavailable);
    } on OAuthFailure {
      rethrow;
    } on Object {
      throw const OAuthFailure(OAuthFailureKind.browserUnavailable);
    } finally {
      timeoutTimer?.cancel();
      await _ignoreFailure(callbackSubscription?.cancel);
      await _ignoreFailure(browserSubscription?.cancel);
      await _ignoreFailure(server?.close);
      await _ignoreFailure(browser?.dispose);
    }
  }

  Future<TokenBundle> _exchangeCode({
    required OAuthConfig config,
    required OAuthMaterial material,
    required Uri redirectUri,
    required String code,
  }) async {
    late final http.Response response;
    try {
      response = switch (config.provider) {
        ProviderId.codex =>
          await _client
              .post(
                Uri.parse(config.tokenEndpoint),
                headers: const {'Accept': 'application/json'},
                body: {
                  'grant_type': 'authorization_code',
                  'code': code,
                  'redirect_uri': redirectUri.toString(),
                  'client_id': config.clientId,
                  'code_verifier': material.verifier,
                },
              )
              .timeout(const Duration(seconds: 15)),
        ProviderId.claude =>
          await _client
              .post(
                Uri.parse(config.tokenEndpoint),
                headers: const {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'grant_type': 'authorization_code',
                  'code': code,
                  'redirect_uri': redirectUri.toString(),
                  'client_id': config.clientId,
                  'code_verifier': material.verifier,
                  'state': material.state,
                }),
              )
              .timeout(const Duration(seconds: 15)),
      };
    } on Object {
      throw const OAuthFailure(OAuthFailureKind.tokenExchange);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const OAuthFailure(OAuthFailureKind.tokenExchange);
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const FormatException();
      }
      final body = decoded.cast<String, Object?>();
      final accessToken = _requiredToken(body['access_token']);
      final refreshToken = _requiredToken(body['refresh_token']);
      final idToken = _optionalToken(body['id_token']);
      final accessPayload = decodeJwtPayload(accessToken);
      final idPayload = decodeJwtPayload(idToken);
      final expiresIn = body['expires_in'];
      final now = DateTime.now();
      return TokenBundle(
        provider: config.provider,
        accessToken: accessToken,
        refreshToken: refreshToken,
        idToken: idToken,
        obtainedAt: now,
        expiresAt:
            jwtExpiry(accessPayload) ??
            (expiresIn is num
                ? now.add(Duration(seconds: expiresIn.toInt()))
                : null),
        accountId: config.provider == ProviderId.codex
            ? jwtStringClaim(accessPayload, 'chatgpt_account_id') ??
                  jwtStringClaim(idPayload, 'chatgpt_account_id')
            : null,
        accountHint:
            maskedEmailFromPayload(accessPayload) ??
            maskedEmailFromPayload(idPayload),
        accountFingerprint: identityFingerprintFromPayloads(
          accessPayload,
          idPayload,
        ),
      );
    } on OAuthFailure {
      rethrow;
    } on Object {
      throw const OAuthFailure(OAuthFailureKind.invalidResponse);
    }
  }

  String _requiredToken(Object? value) {
    final token = _optionalToken(value);
    if (token == null) {
      throw const OAuthFailure(OAuthFailureKind.invalidResponse);
    }
    return token;
  }

  String? _optionalToken(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }

  Future<void> _ignoreFailure(Future<void> Function()? action) async {
    try {
      await action?.call();
    } on Object {
      // Cleanup and a best-effort browser close must not replace the result.
    }
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
