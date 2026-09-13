import 'dart:async';

import 'package:cc_trace_mobile/app/app_controller.dart';
import 'package:cc_trace_mobile/diagnostics/app_diagnostics.dart';
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

  test('a manual refresh is not blocked by a credential failure', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(fakeToken(ProviderId.codex, now: now));
    final gateway = FakeProviderGateway(
      (provider) async => ProviderFetchResult.failure(
        provider: provider,
        failure: ProviderFetchFailureKind.credentials,
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
      controller.provider(ProviderId.codex).errorKind,
      ErrorKind.credentials,
    );
    expect(gateway.calls, [ProviderId.codex]);

    // 自动路径仍然挡住，避免对真失效的凭据反复轮询。
    await controller.refreshProvider(ProviderId.codex);
    expect(gateway.calls, [ProviderId.codex]);

    // 手动路径放行：判定可能来自一次网络异常，用户下拉一次就该能自愈。
    await controller.refreshProvider(ProviderId.codex, manual: true);
    expect(gateway.calls, [ProviderId.codex, ProviderId.codex]);

    await controller.refreshAll(manual: true);
    expect(gateway.calls.length, 3);
    controller.dispose();
  });

  test('a non-credential outcome lifts the credential block', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(fakeToken(ProviderId.codex, now: now));
    var failure = ProviderFetchFailureKind.credentials;
    var clock = now;
    final gateway = FakeProviderGateway(
      (provider) async =>
          ProviderFetchResult.failure(provider: provider, failure: failure),
    );
    final controller = AppController(
      credentials: credentials,
      localStore: MemoryLocalStore()..installed = true,
      oauth: FakeOAuthGateway(),
      providerApi: gateway,
      now: () => clock,
    );

    await controller.bootstrap();
    expect(gateway.calls.length, 1);

    // 网络还没好，手动刷新换来 offline：这一次就足以推翻上次的凭据判定。
    failure = ProviderFetchFailureKind.offline;
    await controller.refreshProvider(ProviderId.codex, manual: true);
    expect(gateway.calls.length, 2);
    expect(controller.provider(ProviderId.codex).errorKind, isNull);
    expect(
      controller.provider(ProviderId.codex).availability,
      ProviderAvailability.offline,
    );

    // 自动路径随之恢复，不必再让用户手动刷一次。越过 offline 那一档退避即可。
    clock = now.add(const Duration(minutes: 2));
    await controller.refreshProvider(ProviderId.codex);
    expect(gateway.calls.length, 3);
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

  test('manual refresh is refused during the ten second throttle', () async {
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
    expect(controller.notice, contains('10 秒后'));
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

  test('sign-in releases the login sheet before the usage refresh', () async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    final local = MemoryLocalStore()..installed = true;
    final fetchStarted = Completer<void>();
    final fetch = Completer<ProviderFetchResult>();
    late final AppController controller;
    ProviderId? authorizingWhenFetchStarted;

    final gateway = FakeProviderGateway((provider) {
      // 用量请求已经发出，登录本身早已结束：此刻面板不能还开着。
      authorizingWhenFetchStarted = controller.authorizing;
      fetchStarted.complete();
      return fetch.future;
    });
    controller = AppController(
      credentials: credentials,
      localStore: local,
      oauth: FakeOAuthGateway(
        onSignIn: (_) async => fakeToken(ProviderId.codex, now: now),
      ),
      providerApi: gateway,
      now: () => now,
    );

    final flow = controller.signIn(ProviderId.codex);
    await fetchStarted.future;

    expect(authorizingWhenFetchStarted, isNull);
    expect(controller.authorizing, isNull);
    expect(controller.authPhase, isNull);

    fetch.complete(fakeSuccess(ProviderId.codex, now: now, remaining: 42));
    await flow;

    expect(
      controller.provider(ProviderId.codex).snapshot?.primary.remainingPercent,
      42,
    );
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

  test('auto refresh runs again after the backoff window expires', () async {
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
  });

  test('a failed refresh lands in the diagnostics log', () async {
    final now = DateTime(2026, 7, 29, 9);
    final diagnostics = AppDiagnostics(now: () => now);
    final credentials = MemoryCredentialsStore();
    await credentials.write(fakeToken(ProviderId.codex, now: now));
    final controller = AppController(
      credentials: credentials,
      localStore: MemoryLocalStore()..installed = true,
      oauth: FakeOAuthGateway(),
      providerApi: FakeProviderGateway(
        (provider) async => ProviderFetchResult.failure(
          provider: provider,
          failure: ProviderFetchFailureKind.offline,
        ),
      ),
      now: () => now,
      diagnostics: diagnostics,
    );

    await controller.bootstrap();

    final exported = diagnostics.export();
    expect(exported, contains('bootstrap.done'));
    expect(exported, contains('refresh.failed'));
    expect(exported, contains('provider=codex'));
    expect(exported, contains('kind=offline'));
    // 退避时长是判断「为什么迟迟不重试」的关键。
    expect(exported, contains('retryInSec=30'));
    // 账号信息一律不入日志。
    expect(exported, isNot(contains('@')));
    controller.dispose();
    diagnostics.dispose();
  });

  test('recovering from a failure is logged, a plain success is not', () async {
    var now = DateTime(2026, 7, 29, 9);
    final diagnostics = AppDiagnostics(now: () => now);
    final credentials = MemoryCredentialsStore();
    await credentials.write(fakeToken(ProviderId.codex, now: now));
    var failing = true;
    final controller = AppController(
      credentials: credentials,
      localStore: MemoryLocalStore()..installed = true,
      oauth: FakeOAuthGateway(),
      providerApi: FakeProviderGateway(
        (provider) async => failing
            ? ProviderFetchResult.failure(
                provider: provider,
                failure: ProviderFetchFailureKind.offline,
              )
            : fakeSuccess(provider, now: now),
      ),
      now: () => now,
      diagnostics: diagnostics,
    );

    await controller.bootstrap();
    expect(diagnostics.export(), isNot(contains('refresh.recovered')));

    failing = false;
    now = now.add(const Duration(minutes: 2));
    await controller.refreshAll(manual: true);
    expect(diagnostics.export(), contains('refresh.recovered'));

    // 已经正常之后再刷一次，不该再添新记录。
    final before = diagnostics.entries.length;
    now = now.add(const Duration(minutes: 2));
    await controller.refreshAll(manual: true);
    expect(diagnostics.entries.length, before);
    controller.dispose();
    diagnostics.dispose();
  });
}
