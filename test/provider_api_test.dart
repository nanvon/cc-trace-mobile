import 'dart:async';
import 'dart:convert';

import 'package:cc_trace_mobile/auth/oauth_config.dart';
import 'package:cc_trace_mobile/auth/token_bundle.dart';
import 'package:cc_trace_mobile/domain/quota_models.dart';
import 'package:cc_trace_mobile/providers/provider_api.dart';
import 'package:cc_trace_mobile/storage/credentials_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Codex quota succeeds even when reset credits fail', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(
      TokenBundle(
        provider: ProviderId.codex,
        accessToken: 'access',
        refreshToken: 'refresh',
        obtainedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
        accountId: 'account-id',
        accountHint: 'sample@example.com',
      ),
    );
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      expect(request.headers['authorization'], 'Bearer access');
      expect(request.headers['chatgpt-account-id'], 'account-id');
      if (request.url.toString() == resetCreditsEndpoint) {
        return http.Response('{}', 500);
      }
      return http.Response(
        jsonEncode({
          'plan_type': 'plus',
          'rate_limit': {
            'primary_window': {
              'used_percent': 41,
              'limit_window_seconds': 604800,
              'reset_after_seconds': 3600,
            },
          },
        }),
        200,
      );
    });
    final api = ProviderApi(
      credentials: credentials,
      client: client,
      now: () => now,
    );

    final result = await api.fetch(ProviderId.codex);

    expect(result.isSuccess, isTrue);
    expect(result.snapshot?.primary.remainingPercent, 59);
    expect(result.resetCredits, isNull);
    expect(requested, hasLength(2));
  });

  test('refreshes an expired Claude token before requesting usage', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(
      TokenBundle(
        provider: ProviderId.claude,
        accessToken: 'expired',
        refreshToken: 'refresh',
        obtainedAt: now.subtract(const Duration(hours: 2)),
        expiresAt: now.subtract(const Duration(minutes: 1)),
      ),
    );
    var refreshRequests = 0;
    final client = MockClient((request) async {
      if (request.url.toString() ==
          providerConfigs[ProviderId.claude]!.tokenEndpoint) {
        refreshRequests++;
        expect(request.method, 'POST');
        expect(
          request.headers['content-type'],
          startsWith('application/x-www-form-urlencoded'),
        );
        expect(Uri.splitQueryString(request.body), {
          'grant_type': 'refresh_token',
          'refresh_token': 'refresh',
          'client_id': providerConfigs[ProviderId.claude]!.clientId,
        });
        return http.Response(
          '{"access_token":"new-access","expires_in":3600}',
          200,
        );
      }
      if (request.url.toString() == claudeProfileEndpoint) {
        expect(request.headers['authorization'], 'Bearer new-access');
        expect(request.headers['content-type'], 'application/json');
        return http.Response('''
          {
            "account": {
              "uuid": "account-uuid",
              "email": "sample@example.com",
              "display_name": "Example User"
            },
            "organization": {"uuid": "organization-uuid"}
          }
          ''', 200);
      }
      expect(request.headers['authorization'], 'Bearer new-access');
      expect(request.headers['anthropic-beta'], 'oauth-2025-04-20');
      return http.Response('''
        {
          "subscriptionType": "pro",
          "five_hour": {"utilization": 22},
          "seven_day": {"utilization": 45}
        }
        ''', 200);
    });
    final api = ProviderApi(
      credentials: credentials,
      client: client,
      now: () => now,
    );

    final result = await api.fetch(ProviderId.claude);

    expect(result.isSuccess, isTrue);
    expect(refreshRequests, 1);
    expect(
      (await credentials.read(ProviderId.claude))?.accessToken,
      'new-access',
    );
    expect(result.identity?.accountHint, 'sample@example.com');
    expect(
      (await credentials.read(ProviderId.claude))?.accountHint,
      'sample@example.com',
    );
    expect(
      (await credentials.read(ProviderId.claude))?.accountFingerprint,
      isNotNull,
    );
  });

  test(
    'refreshes once after a 401 when an opaque token has no expiry',
    () async {
      final now = DateTime(2026, 7, 29, 9);
      final credentials = MemoryCredentialsStore();
      await credentials.write(
        TokenBundle(
          provider: ProviderId.claude,
          accessToken: 'opaque-old',
          refreshToken: 'refresh',
          obtainedAt: now.subtract(const Duration(days: 1)),
        ),
      );
      var usageRequests = 0;
      var refreshRequests = 0;
      final api = ProviderApi(
        credentials: credentials,
        client: MockClient((request) async {
          if (request.url.toString() ==
              providerConfigs[ProviderId.claude]!.tokenEndpoint) {
            refreshRequests++;
            return http.Response(
              '{"access_token":"opaque-new","expires_in":3600}',
              200,
            );
          }
          if (request.url.toString() == claudeProfileEndpoint) {
            return http.Response('''
              {
                "account": {
                  "uuid": "account-uuid",
                  "email": "sample@example.com"
                },
                "organization": {"uuid": "organization-uuid"}
              }
              ''', 200);
          }
          usageRequests++;
          if (request.headers['authorization'] == 'Bearer opaque-old') {
            return http.Response('{}', 401);
          }
          expect(request.headers['authorization'], 'Bearer opaque-new');
          return http.Response('''
          {
            "five_hour": {"utilization": 22},
            "seven_day": {"utilization": 45}
          }
          ''', 200);
        }),
        now: () => now,
      );

      final result = await api.fetch(ProviderId.claude);

      expect(result.isSuccess, isTrue);
      expect(usageRequests, 2);
      expect(refreshRequests, 1);
    },
  );

  test('Claude plan comes from the profile organization type', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(
      TokenBundle(
        provider: ProviderId.claude,
        accessToken: 'access',
        refreshToken: 'refresh',
        obtainedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      ),
    );
    var profileRequests = 0;
    final client = MockClient((request) async {
      if (request.url.toString() == claudeProfileEndpoint) {
        profileRequests++;
        return http.Response('''
          {
            "account": {"uuid": "account-uuid", "email": "sample@example.com"},
            "organization": {
              "uuid": "organization-uuid",
              "organization_type": "claude_pro",
              "rate_limit_tier": "default_claude_pro"
            }
          }
          ''', 200);
      }
      // usage 顶层没有任何套餐字段，真实响应就是这样。
      return http.Response('''
        {
          "five_hour": {"utilization": 22},
          "seven_day": {"utilization": 45}
        }
        ''', 200);
    });
    final api = ProviderApi(
      credentials: credentials,
      client: client,
      now: () => now,
    );

    final result = await api.fetch(ProviderId.claude);

    expect(result.identity?.plan, 'Pro');
    // 套餐名随凭据留存，profile 不随每次刷新调用。
    expect((await credentials.read(ProviderId.claude))?.plan, 'Pro');

    // 第二次取数不该再打 profile：身份和套餐都已齐备。
    await api.fetch(ProviderId.claude);
    expect(profileRequests, 1);
    expect((await api.fetch(ProviderId.claude)).identity?.plan, 'Pro');
  });

  test('an unmapped organization type leaves the plan empty', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(
      TokenBundle(
        provider: ProviderId.claude,
        accessToken: 'access',
        refreshToken: 'refresh',
        obtainedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      ),
    );
    final api = ProviderApi(
      credentials: credentials,
      client: MockClient((request) async {
        if (request.url.toString() == claudeProfileEndpoint) {
          return http.Response('''
            {
              "account": {"uuid": "uuid", "email": "sample@example.com"},
              "organization": {
                "uuid": "organization-uuid",
                "organization_type": "claude_something_new",
                "rate_limit_tier": "default_claude_max_20x"
              }
            }
            ''', 200);
        }
        return http.Response('''
          {
            "five_hour": {"utilization": 22},
            "seven_day": {"utilization": 45}
          }
          ''', 200);
      }),
      now: () => now,
    );

    final result = await api.fetch(ProviderId.claude);

    // 宁可不显示，也不把内部枚举名或 rate_limit_tier 摆到界面上。
    expect(result.isSuccess, isTrue);
    expect(result.identity?.plan, isNull);
    expect(result.identity?.accountHint, 'sample@example.com');
  });

  test('Claude usage still succeeds when profile is unavailable', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(
      TokenBundle(
        provider: ProviderId.claude,
        accessToken: 'access',
        refreshToken: 'refresh',
        obtainedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      ),
    );
    final api = ProviderApi(
      credentials: credentials,
      client: MockClient((request) async {
        if (request.url.toString() == claudeProfileEndpoint) {
          return http.Response('{}', 500);
        }
        return http.Response('''
          {
            "subscriptionType": "pro",
            "five_hour": {"utilization": 22},
            "seven_day": {"utilization": 45}
          }
          ''', 200);
      }),
      now: () => now,
    );

    final result = await api.fetch(ProviderId.claude);

    expect(result.isSuccess, isTrue);
    expect(result.identity?.accountHint, isNull);
    expect(result.identity?.plan, 'Pro');
  });

  test('returns rate limit and Retry-After without response details', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(
      TokenBundle(
        provider: ProviderId.claude,
        accessToken: 'access',
        refreshToken: 'refresh',
        obtainedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      ),
    );
    final api = ProviderApi(
      credentials: credentials,
      client: MockClient(
        (_) async => http.Response(
          '{"private":"do-not-expose"}',
          429,
          headers: {'retry-after': '120'},
        ),
      ),
      now: () => now,
    );

    final result = await api.fetch(ProviderId.claude);

    expect(result.failure, ProviderFetchFailureKind.rateLimited);
    expect(result.retryAfter, const Duration(seconds: 120));
  });

  test('Codex refresh sends the verified least-privilege scope', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(
      TokenBundle(
        provider: ProviderId.codex,
        accessToken: 'expired',
        refreshToken: 'refresh',
        obtainedAt: now.subtract(const Duration(hours: 2)),
        expiresAt: now.subtract(const Duration(minutes: 1)),
      ),
    );
    final api = ProviderApi(
      credentials: credentials,
      client: MockClient((request) async {
        if (request.url.toString() ==
            providerConfigs[ProviderId.codex]!.tokenEndpoint) {
          expect(
            Uri.splitQueryString(request.body),
            containsPair('scope', 'openid profile email'),
          );
          return http.Response(
            '{"access_token":"new-access","expires_in":3600}',
            200,
          );
        }
        if (request.url.toString() == resetCreditsEndpoint) {
          return http.Response('{}', 500);
        }
        expect(request.headers['authorization'], 'Bearer new-access');
        return http.Response(
          jsonEncode({
            'rate_limit': {
              'primary_window': {
                'used_percent': 41,
                'limit_window_seconds': 604800,
                'reset_after_seconds': 3600,
              },
            },
          }),
          200,
        );
      }),
      now: () => now,
    );

    final result = await api.fetch(ProviderId.codex);

    expect(result.isSuccess, isTrue);
  });

  test(
    'does not restore credentials after a refresh races with sign-out',
    () async {
      final now = DateTime(2026, 7, 29, 9);
      final credentials = MemoryCredentialsStore();
      final oldToken = TokenBundle(
        provider: ProviderId.claude,
        accessToken: 'expired',
        refreshToken: 'old-refresh',
        obtainedAt: now.subtract(const Duration(hours: 2)),
        expiresAt: now.subtract(const Duration(minutes: 1)),
      );
      await credentials.write(oldToken);
      final refreshStarted = Completer<void>();
      final refreshResponse = Completer<http.Response>();
      final api = ProviderApi(
        credentials: credentials,
        client: MockClient((request) async {
          if (request.url.toString() ==
              providerConfigs[ProviderId.claude]!.tokenEndpoint) {
            refreshStarted.complete();
            return refreshResponse.future;
          }
          fail('a superseded refresh must not request usage');
        }),
        now: () => now,
      );

      final fetch = api.fetch(ProviderId.claude);
      await refreshStarted.future;
      await credentials.delete(ProviderId.claude);
      refreshResponse.complete(
        http.Response('{"access_token":"old-new","expires_in":3600}', 200),
      );

      final result = await fetch;

      expect(result.failure, ProviderFetchFailureKind.superseded);
      expect(await credentials.read(ProviderId.claude), isNull);
    },
  );

  test(
    'does not overwrite a newer sign-in when an old refresh completes',
    () async {
      final now = DateTime(2026, 7, 29, 9);
      final credentials = MemoryCredentialsStore();
      await credentials.write(
        TokenBundle(
          provider: ProviderId.claude,
          accessToken: 'expired',
          refreshToken: 'old-refresh',
          obtainedAt: now.subtract(const Duration(hours: 2)),
          expiresAt: now.subtract(const Duration(minutes: 1)),
        ),
      );
      final refreshStarted = Completer<void>();
      final refreshResponse = Completer<http.Response>();
      final api = ProviderApi(
        credentials: credentials,
        client: MockClient((request) async {
          if (request.url.toString() ==
              providerConfigs[ProviderId.claude]!.tokenEndpoint) {
            refreshStarted.complete();
            return refreshResponse.future;
          }
          fail('a superseded refresh must not request usage');
        }),
        now: () => now,
      );

      final fetch = api.fetch(ProviderId.claude);
      await refreshStarted.future;
      await credentials.write(
        TokenBundle(
          provider: ProviderId.claude,
          accessToken: 'new-login-access',
          refreshToken: 'new-login-refresh',
          obtainedAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      );
      refreshResponse.complete(
        http.Response('{"access_token":"old-new","expires_in":3600}', 200),
      );

      final result = await fetch;

      expect(result.failure, ProviderFetchFailureKind.superseded);
      expect(
        (await credentials.read(ProviderId.claude))?.accessToken,
        'new-login-access',
      );
    },
  );
}
