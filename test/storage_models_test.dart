import 'dart:convert';

import 'package:cc_trace_mobile/auth/token_bundle.dart';
import 'package:cc_trace_mobile/domain/quota_models.dart';
import 'package:cc_trace_mobile/storage/credentials_store.dart';
import 'package:cc_trace_mobile/storage/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'test_fakes.dart';

void main() {
  test('quota cache survives a real JSON encode and decode round trip', () {
    final now = DateTime(2026, 7, 29, 9);
    final original = ProviderViewState(
      provider: ProviderId.codex,
      refresh: RefreshState.idle,
      freshness: SnapshotFreshness.live,
      availability: ProviderAvailability.ready,
      isSignedIn: true,
      identity: const ProviderIdentity(
        accountHint: 'sample@example.com',
        plan: 'Plus',
        identityKey: 'identity',
      ),
      snapshot: fakeSnapshot(ProviderId.codex, now: now),
      resetCredits: ResetCreditsSnapshot(
        availableCount: 3,
        earliestExpiry: now.add(const Duration(days: 6)),
        availableCredits: [
          ResetCreditEntry(
            id: 'credit-1',
            resetType: 'codex_rate_limits',
            grantedAt: now,
            expiresAt: now.add(const Duration(days: 6)),
          ),
        ],
      ),
      lastSuccessAt: now,
    );
    final decoded = jsonDecode(jsonEncode(original.toCacheJson()));
    final restored = ProviderViewState.fromCacheJson(
      (decoded as Map).cast<String, Object?>(),
    );

    expect(restored.provider, ProviderId.codex);
    expect(restored.snapshot?.primary.remainingPercent, 59);
    expect(restored.identity?.plan, 'Plus');
    expect(restored.resetCredits?.availableCount, 3);
    expect(restored.resetCredits?.availableCredits.single.id, 'credit-1');
    expect(restored.resetCredits?.availableCredits.single.expiresAt?.day, 4);
    expect(restored.freshness, SnapshotFreshness.stale);
  });

  test(
    'quota cache accepts reset credit summaries from the previous schema',
    () {
      final restored = ResetCreditsSnapshot.fromJson({
        'availableCount': 2,
        'earliestExpiry': '2026-08-04T00:00:00.000Z',
      });

      expect(restored.availableCount, 2);
      expect(restored.earliestExpiry?.day, 4);
      expect(restored.availableCredits, isEmpty);
    },
  );

  test(
    'quota cache accepts a window written with the former isActive field',
    () {
      final now = DateTime(2026, 7, 29, 9);
      final original = ProviderViewState(
        provider: ProviderId.claude,
        refresh: RefreshState.idle,
        freshness: SnapshotFreshness.live,
        availability: ProviderAvailability.ready,
        isSignedIn: true,
        snapshot: fakeSnapshot(ProviderId.claude, now: now),
        lastSuccessAt: now,
      );
      final cache = original.toCacheJson();
      final snapshot = (cache['snapshot']! as Map<String, Object?>);
      final windows = snapshot['windows']! as List<Object?>;
      (windows.first! as Map<String, Object?>)['isActive'] = false;

      final restored = ProviderViewState.fromCacheJson(cache);

      expect(restored.snapshot?.primary.remainingPercent, 78);
    },
  );

  test('credential schema remains compatible when fingerprint is absent', () {
    final token = fakeToken(ProviderId.claude, opaqueIdentity: false);
    final json = token.toJson()..remove('accountFingerprint');

    final restored = TokenBundle.fromJson(json);

    expect(restored.accessToken, token.accessToken);
    expect(restored.accountFingerprint, isNull);
    expect(restored.identityKey, isNotNull);
  });

  test('fresh install marker clears residual credentials only once', () async {
    final credentials = MemoryCredentialsStore();
    await credentials.write(fakeToken(ProviderId.codex));
    final local = MemoryLocalStore();

    await local.prepareInstall(credentials);
    expect(await credentials.read(ProviderId.codex), isNull);

    await credentials.write(fakeToken(ProviderId.codex));
    await local.prepareInstall(credentials);
    expect(await credentials.read(ProviderId.codex), isNotNull);
  });

  test('cache v2 never serializes the account hint', () {
    final now = DateTime(2026, 7, 29, 9);
    final original = ProviderViewState(
      provider: ProviderId.codex,
      refresh: RefreshState.idle,
      freshness: SnapshotFreshness.live,
      availability: ProviderAvailability.ready,
      isSignedIn: true,
      identity: const ProviderIdentity(
        accountHint: 'sample@example.com',
        plan: 'Plus',
        identityKey: 'identity',
      ),
      snapshot: fakeSnapshot(ProviderId.codex, now: now),
      lastSuccessAt: now,
    );

    final encoded = jsonEncode(original.toCacheJson());

    expect(encoded, isNot(contains('sample@example.com')));
    final decoded = jsonDecode(encoded) as Map<String, Object?>;
    final restored = ProviderViewState.fromCacheJson(decoded);
    expect(restored.identity?.plan, 'Plus');
    expect(restored.identity?.identityKey, 'identity');
    expect(restored.identity?.accountHint, isNull);
  });

  test('cache v1 stays readable and drops the email on upgrade', () async {
    final now = DateTime(2026, 7, 29, 9);
    final memory = InMemorySharedPreferencesAsync.empty();
    SharedPreferencesAsyncPlatform.instance = memory;
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
    final preferences = SharedPreferencesAsync();
    final local = SharedPreferencesLocalStore(preferences: preferences);
    final v1Cache = jsonEncode({
      'schemaVersion': 1,
      'providers': [
        ProviderViewState(
          provider: ProviderId.codex,
          refresh: RefreshState.idle,
          freshness: SnapshotFreshness.live,
          availability: ProviderAvailability.ready,
          isSignedIn: true,
          identity: const ProviderIdentity(
            accountHint: 'sample@example.com',
            plan: 'Plus',
            identityKey: 'identity',
          ),
          snapshot: fakeSnapshot(ProviderId.codex, now: now),
          lastSuccessAt: now,
        ).toCacheJson(),
      ],
    });
    await preferences.setString('quotaCache.v1', v1Cache);

    final restored = await local.readQuotaCache();

    expect(restored, hasLength(1));
    expect(restored.single.identity?.identityKey, 'identity');
    expect(restored.single.identity?.plan, 'Plus');
    expect(restored.single.identity?.accountHint, isNull);

    await local.writeQuotaCache(restored);
    final writtenRaw = await preferences.getString('quotaCache.v1');
    expect(writtenRaw, isNotNull);
    final written = jsonDecode(writtenRaw!) as Map<String, Object?>;
    expect(written['schemaVersion'], 2);
    expect(
      jsonEncode(written),
      isNot(contains('sample@example.com')),
    );
  });
}
