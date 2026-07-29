import 'dart:convert';

import 'package:cc_trace_mobile/auth/token_bundle.dart';
import 'package:cc_trace_mobile/domain/quota_models.dart';
import 'package:cc_trace_mobile/storage/credentials_store.dart';
import 'package:cc_trace_mobile/storage/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
