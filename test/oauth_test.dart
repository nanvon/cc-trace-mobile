import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cc_trace_mobile/auth/oauth_callback_server.dart';
import 'package:cc_trace_mobile/auth/oauth_config.dart';
import 'package:cc_trace_mobile/auth/oauth_coordinator.dart';
import 'package:cc_trace_mobile/auth/oauth_material.dart';
import 'package:cc_trace_mobile/auth/token_bundle.dart';
import 'package:cc_trace_mobile/domain/quota_models.dart';
import 'package:cc_trace_mobile/q3/browser_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('OAuth configs keep the verified loopback and provider differences', () {
    final codex = providerConfigs[ProviderId.codex]!;
    final claude = providerConfigs[ProviderId.claude]!;

    expect(codex.ports, [1455, 1457]);
    expect(codex.redirectUri(1455).toString(), contains('localhost:1455'));
    expect(codex.callbackPath, '/auth/callback');
    expect(claude.ports, [41999]);
    expect(claude.callbackPath, '/callback');
    expect(claude.extraAuthorizeParameters['code'], 'true');

    final material = createOAuthMaterial();
    final uri = codex.authorizeUri(
      port: 1455,
      state: material.state,
      challenge: material.challenge,
    );
    expect(uri.queryParameters['code_challenge_method'], 'S256');
    expect(uri.queryParameters['state'], material.state);
    expect(material.verifier, isNot(material.challenge));
    expect(material.toString(), isNot(contains(material.verifier)));
  });

  test(
    'TokenBundle never prints credentials and derives a stable identity',
    () {
      final token = TokenBundle(
        provider: ProviderId.codex,
        accessToken: 'access-secret',
        refreshToken: 'refresh-secret',
        obtainedAt: DateTime(2026, 7, 29),
        accountId: 'account-123',
      );

      expect(token.toString(), isNot(contains('access-secret')));
      expect(token.toString(), isNot(contains('refresh-secret')));
      expect(token.identityKey, hasLength(16));
    },
  );

  test('JWT helpers parse namespaced claims without logging the token', () {
    final payload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'exp': 1785300000,
              'https://api.openai.com/auth': {
                'chatgpt_account_id': 'account-123',
                'email': 'sample@example.com',
              },
            }),
          ),
        )
        .replaceAll('=', '');
    final decoded = decodeJwtPayload('header.$payload.signature');

    expect(jwtStringClaim(decoded, 'chatgpt_account_id'), 'account-123');
    expect(emailFromPayload(decoded), 'sample@example.com');
    expect(jwtExpiry(decoded), isNotNull);
    expect(identityFingerprintFromPayloads(decoded, null), hasLength(16));
  });

  test('stored credentials restore the full email from the JWT', () {
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'email': 'sample@example.com'})))
        .replaceAll('=', '');

    final token = TokenBundle.fromJson({
      'schemaVersion': 1,
      'provider': 'codex',
      'accessToken': 'header.$payload.signature',
      'refreshToken': 'refresh-secret',
      'idToken': null,
      'obtainedAt': '2026-07-29T00:00:00.000Z',
      'expiresAt': null,
      'accountId': null,
      'accountHint': 'sa•••@example.com',
      'accountFingerprint': null,
    });

    expect(token.accountHint, 'sample@example.com');
  });

  test(
    'callback server rejects bad state, then accepts a valid callback',
    () async {
      final config = OAuthConfig(
        provider: ProviderId.claude,
        authorizeEndpoint: 'https://example.com/authorize',
        tokenEndpoint: 'https://example.com/token',
        usageEndpoint: 'https://example.com/usage',
        clientId: 'client',
        scopes: 'read',
        callbackPath: '/callback',
        ports: const [0],
        extraAuthorizeParameters: const {},
      );
      final server = await OAuthCallbackServer.bind(
        config: config,
        expectedState: 'expected',
      );
      final events = <OAuthCallbackEvent>[];
      final subscription = server.events.listen(events.add);

      await _get(
        Uri.parse(
          'http://127.0.0.1:${server.port}/callback?code=secret&state=wrong',
        ),
      );
      await _get(
        Uri.parse(
          'http://127.0.0.1:${server.port}/callback?code=secret&state=expected',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events.map((event) => event.kind), [
        OAuthCallbackKind.invalid,
        OAuthCallbackKind.accepted,
      ]);
      expect(events.last.toString(), isNot(contains('secret')));

      await subscription.cancel();
      await server.close();
    },
  );

  test(
    'Android browser return does not cancel a delayed localhost callback',
    () async {
      const config = OAuthConfig(
        provider: ProviderId.codex,
        authorizeEndpoint: 'https://example.test/authorize',
        tokenEndpoint: 'https://example.test/token',
        usageEndpoint: 'https://example.test/usage',
        clientId: 'client',
        scopes: 'openid',
        callbackPath: '/auth/callback',
        ports: [0],
        extraAuthorizeParameters: {},
      );
      final browser = _DelayedLoopbackBrowser();
      final coordinator = OAuthCoordinator(
        browserFactory: () => browser,
        configs: const {ProviderId.codex: config},
        client: MockClient((request) async {
          expect(request.url, Uri.parse(config.tokenEndpoint));
          expect(request.method, 'POST');
          return http.Response(
            jsonEncode({
              'access_token': 'header.e30.signature',
              'refresh_token': 'refresh-token',
              'expires_in': 3600,
            }),
            HttpStatus.ok,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final token = await coordinator.signIn(ProviderId.codex);

      expect(token.provider, ProviderId.codex);
      coordinator.dispose();
    },
  );
}

class _DelayedLoopbackBrowser implements BrowserLauncher {
  final StreamController<OAuthBrowserEvent> _events =
      StreamController<OAuthBrowserEvent>.broadcast(sync: true);

  @override
  Stream<OAuthBrowserEvent> get events => _events.stream;

  @override
  Future<void> open(Uri authorizeUri) async {
    _events.add(const OAuthBrowserEvent(OAuthBrowserEventType.returned));
    await Future<void>.delayed(const Duration(milliseconds: 1600));

    final redirectUri = Uri.parse(
      authorizeUri.queryParameters['redirect_uri']!,
    );
    final callbackUri = redirectUri.replace(
      host: InternetAddress.loopbackIPv4.address,
      queryParameters: {
        'code': 'test-code',
        'state': authorizeUri.queryParameters['state']!,
      },
    );
    await _get(callbackUri);
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> release() async {}

  @override
  Future<void> dispose() => _events.close();
}

Future<void> _get(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    await response.drain<void>();
  } finally {
    client.close(force: true);
  }
}
