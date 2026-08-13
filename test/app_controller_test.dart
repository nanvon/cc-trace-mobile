import 'dart:async';

import 'package:cc_trace_mobile/app/app_controller.dart';
import 'package:cc_trace_mobile/domain/quota_models.dart';
import 'package:cc_trace_mobile/providers/provider_api.dart';
import 'package:cc_trace_mobile/storage/credentials_store.dart';
import 'package:cc_trace_mobile/storage/local_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'uses a current cache immediately without an unnecessary request',
    () async {
      final now = DateTime(2026, 7, 29, 9);
      final credentials = MemoryCredentialsStore();
      final token = fakeToken(ProviderId.codex, now: now);
      await credentials.write(token);
      final local = MemoryLocalStore()..installed = true;
      local.cached[ProviderId.codex] = ProviderViewState(
        provider: ProviderId.codex,
        refresh: RefreshState.idle,
        freshness: SnapshotFreshness.stale,
        availability: ProviderAvailability.ready,
        isSignedIn: true,
        identity: ProviderIdentity(identityKey: token.identityKey),
        snapshot: fakeSnapshot(ProviderId.codex, now: now),
        lastSuccessAt: now.subtract(const Duration(minutes: 5)),
      );
      final gateway = FakeProviderGateway(
        (provider) async => fakeSuccess(provider, now: now),
      );
      final oauth = FakeOAuthGateway();
      final controller = AppController(
        credentials: credentials,
        localStore: local,
        oauth: oauth,
        providerApi: gateway,
        now: () => now,
      );

      await controller.bootstrap();

      expect(gateway.calls, isEmpty);
      expect(
        controller.provider(ProviderId.codex).freshness,
        SnapshotFreshness.live,
      );
      controller.dispose();
      expect(oauth.disposed, isTrue);
    },
  );

  test('credential failure preserves the old snapshot as stale', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    final token = fakeToken(ProviderId.codex, now: now);
    await credentials.write(token);
    final local = MemoryLocalStore()..installed = true;
    local.cached[ProviderId.codex] = ProviderViewState(
      provider: ProviderId.codex,
      refresh: RefreshState.idle,
      freshness: SnapshotFreshness.stale,
      availability: ProviderAvailability.ready,
      isSignedIn: true,
      identity: ProviderIdentity(identityKey: token.identityKey),
      snapshot: fakeSnapshot(ProviderId.codex, now: now),
      lastSuccessAt: now.subtract(const Duration(hours: 1)),
    );
    final gateway = FakeProviderGateway(
      (provider) async => ProviderFetchResult.failure(
        provider: provider,
        failure: ProviderFetchFailureKind.credentials,
      ),
    );
    final controller = AppController(
      credentials: credentials,
      localStore: local,
      oauth: FakeOAuthGateway(),
      providerApi: gateway,
      now: () => now,
    );

    await controller.bootstrap();
    final state = controller.provider(ProviderId.codex);

    expect(state.hasSnapshot, isTrue);
    expect(state.freshness, SnapshotFreshness.stale);
    expect(state.errorKind, ErrorKind.credentials);
    expect(state.resetCredits, isNull);
    expect(gateway.calls, [ProviderId.codex]);
    await controller.refreshProvider(ProviderId.codex);
    expect(gateway.calls, [ProviderId.codex]);
    controller.dispose();
  });

  test(
    'keeps a server Retry-After longer than the local backoff cap',
    () async {
      final now = DateTime(2026, 7, 29, 9);
      final credentials = MemoryCredentialsStore();
      await credentials.write(fakeToken(ProviderId.codex, now: now));
      final gateway = FakeProviderGateway(
        (provider) async => ProviderFetchResult.failure(
          provider: provider,
          failure: ProviderFetchFailureKind.rateLimited,
          retryAfter: const Duration(hours: 1),
        ),
      );
      final controller = AppController(
        credentials: credentials,
        localStore: MemoryLocalStore()..installed = true,
        oauth: FakeOAuthGateway(),
        providerApi: gateway,
        now: () => now,
      );

      await controller.bootstrap();

      expect(
        controller.provider(ProviderId.codex).retryAfter,
        now.add(const Duration(hours: 1)),
      );
      await controller.refreshAll(manual: true);
      expect(gateway.calls, [ProviderId.codex]);
      expect(controller.notice, contains('60 分钟后'));
      controller.dispose();
    },
  );

  test('manual refresh is refused during the one minute throttle', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(fakeToken(ProviderId.codex, now: now));
    final local = MemoryLocalStore()..installed = true;
    final gateway = FakeProviderGateway(
      (provider) async => fakeSuccess(provider, now: now),
    );
    final controller = AppController(
      credentials: credentials,
      localStore: local,
      oauth: FakeOAuthGateway(),
      providerApi: gateway,
      now: () => now,
    );
    await controller.bootstrap();
    final startupCalls = gateway.calls.length;

    await controller.refreshAll(manual: true);
    final afterFirstManual = gateway.calls.length;
    await controller.refreshAll(manual: true);

    expect(afterFirstManual, startupCalls + 1);
    expect(gateway.calls, hasLength(afterFirstManual));
    expect(controller.notice, contains('1 分钟后'));
    controller.dispose();
  });

  test(
    'identity changes replace rather than merge a cached snapshot',
    () async {
      final now = DateTime(2026, 7, 29, 9);
      final credentials = MemoryCredentialsStore();
      await credentials.write(
        fakeToken(ProviderId.codex, now: now, identity: 'new-account'),
      );
      final local = MemoryLocalStore()..installed = true;
      local.cached[ProviderId.codex] = ProviderViewState(
        provider: ProviderId.codex,
        refresh: RefreshState.idle,
        freshness: SnapshotFreshness.stale,
        availability: ProviderAvailability.ready,
        isSignedIn: true,
        identity: const ProviderIdentity(identityKey: 'old-key'),
        snapshot: fakeSnapshot(ProviderId.codex, now: now),
        lastSuccessAt: now,
      );
      final gateway = FakeProviderGateway(
        (provider) async => fakeSuccess(provider, now: now),
      );
      final controller = AppController(
        credentials: credentials,
        localStore: local,
        oauth: FakeOAuthGateway(),
        providerApi: gateway,
        now: () => now,
      );

      await controller.bootstrap();

      expect(controller.provider(ProviderId.codex).hasSnapshot, isTrue);
      expect(gateway.calls, [ProviderId.codex]);
      controller.dispose();
    },
  );

  test('ignores an in-flight refresh that completes after sign-out', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(fakeToken(ProviderId.codex, now: now));
    final local = MemoryLocalStore()..installed = true;
    final fetchStarted = Completer<void>();
    final fetchResult = Completer<ProviderFetchResult>();
    final gateway = FakeProviderGateway((provider) {
      fetchStarted.complete();
      return fetchResult.future;
    });
    final controller = AppController(
      credentials: credentials,
      localStore: local,
      oauth: FakeOAuthGateway(),
      providerApi: gateway,
      now: () => now,
    );

    final bootstrap = controller.bootstrap();
    await fetchStarted.future;
    await controller.signOut(ProviderId.codex);
    fetchResult.complete(fakeSuccess(ProviderId.codex, now: now));
    await bootstrap;

    expect(controller.provider(ProviderId.codex).isSignedIn, isFalse);
    expect(controller.provider(ProviderId.codex).hasSnapshot, isFalse);
    expect(await credentials.read(ProviderId.codex), isNull);
    expect(local.cached, isEmpty);
    controller.dispose();
  });

  test('a new login wins over an older in-flight refresh', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(
      fakeToken(ProviderId.codex, now: now, identity: 'old-account'),
    );
    final local = MemoryLocalStore()..installed = true;
    final oldFetchStarted = Completer<void>();
    final oldFetch = Completer<ProviderFetchResult>();
    var fetchCount = 0;
    final gateway = FakeProviderGateway((provider) {
      fetchCount++;
      if (fetchCount == 1) {
        oldFetchStarted.complete();
        return oldFetch.future;
      }
      return Future.value(fakeSuccess(provider, now: now, remaining: 55));
    });
    final newToken = fakeToken(
      ProviderId.codex,
      now: now,
      identity: 'new-account',
    ).copyWith(accessToken: 'new-login-access');
    final controller = AppController(
      credentials: credentials,
      localStore: local,
      oauth: FakeOAuthGateway(onSignIn: (_) async => newToken),
      providerApi: gateway,
      now: () => now,
    );

    final bootstrap = controller.bootstrap();
    await oldFetchStarted.future;
    await controller.signIn(ProviderId.codex);
    oldFetch.complete(fakeSuccess(ProviderId.codex, now: now, remaining: 1));
    await bootstrap;

    expect(
      controller.provider(ProviderId.codex).snapshot?.primary.remainingPercent,
      55,
    );
    expect(
      (await credentials.read(ProviderId.codex))?.accessToken,
      'new-login-access',
    );
    expect(
      local.cached[ProviderId.codex]?.snapshot?.primary.remainingPercent,
      55,
    );
    controller.dispose();
  });

  test('opaque Claude re-login clears a previous account snapshot', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(
      fakeToken(ProviderId.claude, now: now, opaqueIdentity: true),
    );
    final local = MemoryLocalStore()..installed = true;
    local.cached[ProviderId.claude] = ProviderViewState(
      provider: ProviderId.claude,
      refresh: RefreshState.idle,
      freshness: SnapshotFreshness.live,
      availability: ProviderAvailability.ready,
      isSignedIn: true,
      snapshot: fakeSnapshot(ProviderId.claude, now: now, remaining: 78),
      lastSuccessAt: now,
    );
    final controller = AppController(
      credentials: credentials,
      localStore: local,
      oauth: FakeOAuthGateway(
        onSignIn: (_) async => fakeToken(
          ProviderId.claude,
          now: now,
          opaqueIdentity: true,
        ).copyWith(accessToken: 'new-opaque-access'),
      ),
      providerApi: FakeProviderGateway(
        (provider) async => ProviderFetchResult.failure(
          provider: provider,
          failure: ProviderFetchFailureKind.credentials,
        ),
      ),
      now: () => now,
    );

    await controller.bootstrap();
    expect(controller.provider(ProviderId.claude).hasSnapshot, isTrue);

    await controller.signIn(ProviderId.claude);

    expect(controller.provider(ProviderId.claude).hasSnapshot, isFalse);
    expect(
      controller.provider(ProviderId.claude).errorKind,
      ErrorKind.credentials,
    );
    expect(local.cached[ProviderId.claude], isNull);
    controller.dispose();
  });

  test(
    'auto refresh stays silent while a provider is held by backoff',
    () async {
      var now = DateTime(2026, 7, 29, 9);
      final credentials = MemoryCredentialsStore();
      await credentials.write(fakeToken(ProviderId.codex, now: now));
      final gateway = FakeProviderGateway(
        (provider) async => ProviderFetchResult.failure(
          provider: provider,
          failure: ProviderFetchFailureKind.rateLimited,
          retryAfter: const Duration(hours: 1),
        ),
      );
      final controller = AppController(
        credentials: credentials,
        localStore: MemoryLocalStore()..installed = true,
        oauth: FakeOAuthGateway(),
        providerApi: gateway,
        now: () => now,
      );

      await controller.bootstrap();
      expect(gateway.calls, [ProviderId.codex]);
      expect(controller.provider(ProviderId.codex).retryAfter, isNotNull);

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 30));
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(gateway.calls, [ProviderId.codex]);
      expect(controller.notice, isNull);
      controller.dispose();
    },
  );

  test(
    'auto refresh runs again after the backoff window expires',
    () async {
      var now = DateTime(2026, 7, 29, 9);
      final credentials = MemoryCredentialsStore();
      await credentials.write(fakeToken(ProviderId.codex, now: now));
      final gateway = FakeProviderGateway(
        (provider) async => ProviderFetchResult.failure(
          provider: provider,
          failure: ProviderFetchFailureKind.rateLimited,
          retryAfter: const Duration(hours: 1),
        ),
      );
      final controller = AppController(
        credentials: credentials,
        localStore: MemoryLocalStore()..installed = true,
        oauth: FakeOAuthGateway(),
        providerApi: gateway,
        now: () => now,
      );

      await controller.bootstrap();
      expect(gateway.calls, [ProviderId.codex]);

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(hours: 1, minutes: 1));
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (controller.isRefreshing && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(gateway.calls, [ProviderId.codex, ProviderId.codex]);
      controller.dispose();
    },
  );
}
