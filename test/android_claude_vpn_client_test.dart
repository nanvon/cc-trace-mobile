import 'dart:async';
import 'dart:convert';

import 'package:cc_trace_mobile/app/app_controller.dart';
import 'package:cc_trace_mobile/auth/oauth_config.dart';
import 'package:cc_trace_mobile/auth/token_bundle.dart';
import 'package:cc_trace_mobile/domain/quota_models.dart';
import 'package:cc_trace_mobile/network/android_claude_vpn_client.dart';
import 'package:cc_trace_mobile/providers/provider_api.dart';
import 'package:cc_trace_mobile/storage/credentials_store.dart';
import 'package:cc_trace_mobile/storage/local_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.nanvon.cctrace.mobile/claude_vpn');
  const provider = ProviderId.claude;
  final config = providerConfigs[provider]!;

  void mockPlatform(Future<Object?> Function(MethodCall) handler) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, handler);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  test(
    'keeps the Claude cache while VPN is down and retries after backoff',
    () async {
      var now = DateTime(2026, 11, 12, 9);
      final capturedAt = now.subtract(const Duration(hours: 1));
      final credentials = MemoryCredentialsStore();
      final expired = TokenBundle(
        provider: provider,
        accessToken: 'synthetic-expired',
        refreshToken: 'synthetic-refresh',
        obtainedAt: now.subtract(const Duration(hours: 2)),
        expiresAt: now.subtract(const Duration(minutes: 1)),
      );
      await credentials.write(expired);
      final cache = fakeSnapshot(provider, now: capturedAt);
      final local = MemoryLocalStore()..installed = true;
      local.cached[provider] = ProviderViewState(
        provider: provider,
        refresh: RefreshState.idle,
        freshness: SnapshotFreshness.stale,
        availability: ProviderAvailability.ready,
        isSignedIn: true,
        snapshot: cache,
        lastSuccessAt: capturedAt,
      );

      var vpnUp = false;
      final requests = <String>[];
      mockPlatform((call) async {
        expect(call.method, 'send');
        final arguments = call.arguments as Map<Object?, Object?>;
        final url = arguments['url'] as String;
        requests.add(url);
        expect(
          arguments['method'],
          url == config.tokenEndpoint ? 'POST' : 'GET',
        );
        if (!vpnUp) throw PlatformException(code: 'VPN_UNAVAILABLE');
        final response = switch (url) {
          final url when url == config.tokenEndpoint =>
            '{"access_token":"synthetic-new","expires_in":3600}',
          final url when url == config.usageEndpoint =>
            '{"five_hour":{"utilization":30}}',
          claudeProfileEndpoint =>
            '{"account":{"uuid":"sample-uuid","email":"sample@example.com"},'
                '"organization":{"organization_type":"claude_pro"}}',
          _ => throw StateError('Unexpected endpoint'),
        };
        return {
          'status': 200,
          'headers': {'content-type': 'application/json'},
          'body': Uint8List.fromList(utf8.encode(response)),
        };
      });
      final controller = AppController(
        credentials: credentials,
        localStore: local,
        oauth: FakeOAuthGateway(),
        providerApi: ProviderApi(
          credentials: credentials,
          client: AndroidClaudeVpnClient(),
          now: () => now,
        ),
        now: () => now,
      );
      addTearDown(controller.dispose);

      await controller.bootstrap();
      expect(requests, [config.tokenEndpoint]);
      final offline = controller.provider(provider);
      expect(offline.availability, ProviderAvailability.offline);
      expect(offline.freshness, SnapshotFreshness.stale);
      expect(offline.snapshot?.primary.remainingPercent, 78);
      expect(offline.lastSuccessAt, capturedAt);
      expect(offline.retryAfter, now.add(const Duration(seconds: 30)));

      vpnUp = true;
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await controller.refreshProvider(provider, manual: true);
      expect(requests, [config.tokenEndpoint]);

      now = now.add(const Duration(seconds: 30));
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(controller.provider(provider).refresh, RefreshState.refreshing);
      await controller.refreshProvider(provider);
      expect(requests, hasLength(4));
      expect(requests[1], config.tokenEndpoint);
      expect(
        requests.skip(2),
        unorderedEquals([config.usageEndpoint, claudeProfileEndpoint]),
      );
      final refreshed = controller.provider(provider);
      expect(refreshed.availability, ProviderAvailability.ready);
      expect(refreshed.snapshot?.primary.remainingPercent, 70);
      expect(refreshed.lastSuccessAt, now);
      expect(refreshed.retryAfter, isNull);
    },
  );

  test('fails offline when the VPN channel is missing', () async {
    final now = DateTime(2026, 11, 12, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(fakeToken(provider, now: now));
    final api = ProviderApi(
      credentials: credentials,
      client: AndroidClaudeVpnClient(),
      now: () => now,
    );

    final result = await api.fetch(provider);
    expect(result.failure, ProviderFetchFailureKind.offline);
  });

  test('abort cancels the same native request', () async {
    final started = Completer<int>();
    final cancelled = Completer<int>();
    final nativeResponse = Completer<Object?>();
    mockPlatform((call) async {
      if (call.method == 'send') {
        final arguments = call.arguments as Map<Object?, Object?>;
        started.complete(arguments['id'] as int);
        return nativeResponse.future;
      }
      expect(call.method, 'cancel');
      cancelled.complete(call.arguments as int);
      nativeResponse.completeError(
        PlatformException(code: 'VPN_REQUEST_FAILED'),
      );
      return null;
    });
    final abort = Completer<void>();
    final client = AndroidClaudeVpnClient();
    final pending = client.send(
      http.AbortableRequest(
        'GET',
        Uri.parse(config.usageEndpoint),
        abortTrigger: abort.future,
      ),
    );
    final result = expectLater(
      pending,
      throwsA(isA<http.RequestAbortedException>()),
    );
    final requestId = await started.future;
    abort.complete();
    await result;
    expect(await cancelled.future, requestId);
  });
}
