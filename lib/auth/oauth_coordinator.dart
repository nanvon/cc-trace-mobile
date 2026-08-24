// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/quota_models.dart';
import '../network/abortable_http.dart';
import '../q3/browser_bridge.dart';
import 'oauth_callback_server.dart';
import 'oauth_config.dart';
import 'oauth_diagnostics.dart';
import 'oauth_keep_alive.dart';
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

/// 登录进行到哪一步，用于让界面给出准确的等待文案与出口。
///
/// [returnedWithoutResult] 是关键的一档：用户已经切回应用但回调还没到。
/// 过去这里只能继续转圈直到超时，现在界面据此给出「换个浏览器重试 / 取消」。
enum OAuthPhase {
  preparing,
  choosingBrowser,
  waitingInBrowser,
  returnedWithoutResult,
  exchanging,
}

class OAuthFailure implements Exception {
  const OAuthFailure(this.kind);

  final OAuthFailureKind kind;

  @override
  String toString() => 'OAuthFailure($kind, <details redacted>)';
}

typedef BrowserLauncherFactory = BrowserLauncher Function();

/// 让用户从设备上的浏览器里挑一个。返回 null 表示用户放弃登录。
typedef BrowserSelector =
    Future<BrowserChoice?> Function(List<BrowserChoice> choices);

abstract interface class OAuthGateway {
  Stream<OAuthPhase> get phases;
  Future<TokenBundle> signIn(ProviderId provider, {BrowserSelector? selector});

  /// 授权页打不开或被误关时，用同一份 PKCE / state 重新打开浏览器，
  /// 不重启整个流程（loopback server 仍在监听）。
  Future<void> reopenBrowser({BrowserSelector? selector});

  void cancel();
  void dispose();
}

class OAuthCoordinator implements OAuthGateway {
  OAuthCoordinator({
    http.Client? client,
    BrowserLauncherFactory? browserFactory,
    Map<ProviderId, OAuthConfig>? configs,
    SignInKeepAlive? keepAlive,
    OAuthDiagnostics? diagnostics,
    this.timeout = const Duration(minutes: 3),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _browserFactory = browserFactory ?? OAuthBrowserBridge.new,
       _configs = configs ?? providerConfigs,
       _keepAlive = keepAlive ?? const PlatformSignInKeepAlive(),
       _diagnostics = diagnostics ?? OAuthDiagnostics.instance;

  final http.Client _client;
  final bool _ownsClient;
  final BrowserLauncherFactory _browserFactory;
  final Map<ProviderId, OAuthConfig> _configs;
  final SignInKeepAlive _keepAlive;
  final OAuthDiagnostics _diagnostics;

  /// Android `shortService` 的前台服务上限也是 3 分钟，两者保持一致，
  /// 避免出现「保活已经结束但界面还在等」的空窗。
  final Duration timeout;

  final StreamController<OAuthPhase> _phases =
      StreamController<OAuthPhase>.broadcast();

  Completer<String>? _pending;
  BrowserLauncher? _activeBrowser;
  Uri? _activeAuthorizeUri;

  @override
  Stream<OAuthPhase> get phases => _phases.stream;

  @override
  Future<TokenBundle> signIn(
    ProviderId provider, {
    BrowserSelector? selector,
  }) async {
    final config = _configs[provider]!;
    final material = createOAuthMaterial();
    OAuthCallbackServer? server;
    BrowserLauncher? browser;
    StreamSubscription<OAuthCallbackEvent>? callbackSubscription;
    StreamSubscription<OAuthBrowserEvent>? browserSubscription;
    Timer? timeoutTimer;
    final result = Completer<String>();
    _pending = result;
    _diagnostics.startSession(provider.name);

    try {
      _emitPhase(OAuthPhase.preparing);
      server = await OAuthCallbackServer.bind(
        config: config,
        expectedState: material.state,
      );
      browser = _browserFactory();
      _activeBrowser = browser;
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
            _diagnostics.record('platform.browserCancelled');
            result.completeError(
              const OAuthFailure(OAuthFailureKind.cancelled),
            );
          case OAuthBrowserEventType.returned:
            // 回到前台不等于取消：合法回调可能还在路上（尤其是回调由浏览器
            // 侧发起、本进程刚被唤醒时）。只把状态告诉界面，由用户决定去留。
            _diagnostics.record('platform.browserReturned');
            _emitPhase(OAuthPhase.returnedWithoutResult);
          case OAuthBrowserEventType.failed:
            _diagnostics.record('platform.browserFailed', {
              'category': event.category ?? 'unknown',
            });
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

      final authorizeUri = config.authorizeUri(
        port: server.port,
        state: material.state,
        challenge: material.challenge,
      );
      _activeAuthorizeUri = authorizeUri;

      final held = await _keepAlive.start();
      _diagnostics.record('keepAlive.start', {'held': held});

      await _openBrowser(browser, authorizeUri, selector);
      final code = await result.future;
      _emitPhase(OAuthPhase.exchanging);
      await _ignoreFailure(browser.close);
      final bundle = await _exchangeCode(
        config: config,
        material: material,
        redirectUri: config.redirectUri(server.port),
        code: code,
      );
      _diagnostics.record('signIn.success', {'provider': provider.name});
      return bundle;
    } on SocketException {
      _diagnostics.record('signIn.failure', {'kind': 'portUnavailable'});
      throw const OAuthFailure(OAuthFailureKind.portUnavailable);
    } on OAuthFailure catch (failure) {
      _diagnostics.record('signIn.failure', {'kind': failure.kind.name});
      rethrow;
    } on Object {
      _diagnostics.record('signIn.failure', {'kind': 'browserUnavailable'});
      throw const OAuthFailure(OAuthFailureKind.browserUnavailable);
    } finally {
      timeoutTimer?.cancel();
      _pending = null;
      _activeBrowser = null;
      _activeAuthorizeUri = null;
      await _ignoreFailure(callbackSubscription?.cancel);
      await _ignoreFailure(browserSubscription?.cancel);
      await _ignoreFailure(server?.close);
      await _ignoreFailure(browser?.dispose);
      await _ignoreFailure(_keepAlive.stop);
    }
  }

  @override
  Future<void> reopenBrowser({BrowserSelector? selector}) async {
    final browser = _activeBrowser;
    final authorizeUri = _activeAuthorizeUri;
    final pending = _pending;
    if (browser == null || authorizeUri == null || pending == null) {
      return;
    }
    if (pending.isCompleted) {
      return;
    }
    _diagnostics.record('browser.reopen');
    try {
      await _openBrowser(browser, authorizeUri, selector);
    } on OAuthFailure catch (failure) {
      if (!pending.isCompleted) {
        pending.completeError(failure);
      }
    } on Object {
      if (!pending.isCompleted) {
        pending.completeError(
          const OAuthFailure(OAuthFailureKind.browserUnavailable),
        );
      }
    }
  }

  @override
  void cancel() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      _diagnostics.record('signIn.cancelledByUser');
      pending.completeError(const OAuthFailure(OAuthFailureKind.cancelled));
    }
  }

  Future<void> _openBrowser(
    BrowserLauncher browser,
    Uri authorizeUri,
    BrowserSelector? selector,
  ) async {
    final choices = await browser.listBrowsers();
    _diagnostics.record('browsers.listed', {
      'count': choices.length,
      'customTabs': choices.where((c) => c.supportsCustomTabs).length,
    });
    BrowserChoice? chosen;
    if (choices.isNotEmpty && selector != null) {
      _emitPhase(OAuthPhase.choosingBrowser);
      chosen = await selector(choices);
      if (chosen == null) {
        throw const OAuthFailure(OAuthFailureKind.cancelled);
      }
      _diagnostics.record('browser.chosen', {
        'pkg': chosen.packageName,
        'customTabs': chosen.supportsCustomTabs,
        'default': chosen.isDefault,
      });
    }
    _emitPhase(OAuthPhase.waitingInBrowser);
    await browser.open(authorizeUri, packageName: chosen?.packageName);
    _diagnostics.record('browser.opened');
  }

  void _emitPhase(OAuthPhase phase) {
    if (!_phases.isClosed) {
      _phases.add(phase);
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
      final request = http.Request(
        'POST',
        Uri.parse(config.tokenEndpoint),
      )..headers.addAll(const {'Accept': 'application/json'});
      if (config.provider == ProviderId.codex) {
        request.bodyFields = {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri.toString(),
          'client_id': config.clientId,
          'code_verifier': material.verifier,
        };
      } else {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode({
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri.toString(),
          'client_id': config.clientId,
          'code_verifier': material.verifier,
          'state': material.state,
        });
      }
      response = await sendWithTimeout(_client, request);
    } on Object {
      _diagnostics.record('token.exchange', {'transport': 'failed'});
      throw const OAuthFailure(OAuthFailureKind.tokenExchange);
    }
    _diagnostics.record('token.exchange', {'status': response.statusCode});
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
            emailFromPayload(accessPayload) ?? emailFromPayload(idPayload),
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
    unawaited(_phases.close());
  }
}
