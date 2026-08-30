import 'dart:async';

import 'package:cc_trace_mobile/auth/oauth_coordinator.dart';
import 'package:cc_trace_mobile/auth/token_bundle.dart';
import 'package:cc_trace_mobile/domain/quota_models.dart';
import 'package:cc_trace_mobile/providers/provider_api.dart';

class FakeOAuthGateway implements OAuthGateway {
  FakeOAuthGateway({this.onSignIn});

  final Future<TokenBundle> Function(ProviderId provider)? onSignIn;
  final StreamController<OAuthPhase> _phases =
      StreamController<OAuthPhase>.broadcast();
  bool disposed = false;
  bool cancelled = false;
  int reopenCount = 0;

  void emitPhase(OAuthPhase phase) => _phases.add(phase);

  @override
  Stream<OAuthPhase> get phases => _phases.stream;

  @override
  Future<TokenBundle> signIn(ProviderId provider, {BrowserSelector? selector}) {
    final callback = onSignIn;
    if (callback == null) {
      throw const OAuthFailure(OAuthFailureKind.cancelled);
    }
    return callback(provider);
  }

  @override
  Future<void> reopenBrowser({BrowserSelector? selector}) async {
    reopenCount += 1;
  }

  @override
  void cancel() {
    cancelled = true;
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(_phases.close());
  }
}

class FakeProviderGateway implements ProviderGateway {
  FakeProviderGateway(this.onFetch);

  final Future<ProviderFetchResult> Function(ProviderId provider) onFetch;
  final List<ProviderId> calls = [];

  @override
  Future<ProviderFetchResult> fetch(ProviderId provider) {
    calls.add(provider);
    return onFetch(provider);
  }
}

TokenBundle fakeToken(
  ProviderId provider, {
  DateTime? now,
  String? identity,
  bool opaqueIdentity = true,
}) {
  final timestamp = now ?? DateTime(2026, 7, 29, 9);
  return TokenBundle(
    provider: provider,
    accessToken: 'access-${provider.name}',
    refreshToken: 'refresh-${provider.name}',
    obtainedAt: timestamp,
    expiresAt: timestamp.add(const Duration(hours: 1)),
    accountId: provider == ProviderId.codex
        ? identity ?? '${provider.name}-account'
        : null,
    accountHint: provider == ProviderId.codex || !opaqueIdentity
        ? 'sample@example.com'
        : null,
    accountFingerprint: provider == ProviderId.claude && !opaqueIdentity
        ? identity
        : null,
  );
}

QuotaSnapshot fakeSnapshot(
  ProviderId provider, {
  DateTime? now,
  double remaining = 59,
  bool includeModel = false,
}) {
  final timestamp = now ?? DateTime(2026, 7, 29, 9);
  if (provider == ProviderId.codex) {
    return QuotaSnapshot(
      capturedAt: timestamp,
      windows: [
        QuotaWindow(
          id: 'codex.weekly',
          kind: QuotaWindowKind.weekly,
          usedPercent: 100 - remaining,
          remainingPercent: remaining,
          resetsAt: timestamp.add(const Duration(days: 2)),
          windowSeconds: 604800,
          isPrimary: true,
        ),
      ],
    );
  }
  return QuotaSnapshot(
    capturedAt: timestamp,
    windows: [
      QuotaWindow(
        id: 'claude.five-hour',
        kind: QuotaWindowKind.fiveHour,
        usedPercent: 22,
        remainingPercent: 78,
        resetsAt: timestamp.add(const Duration(hours: 4)),
        windowSeconds: 18000,
        isPrimary: true,
      ),
      QuotaWindow(
        id: 'claude.weekly',
        kind: QuotaWindowKind.weekly,
        usedPercent: 45,
        remainingPercent: 55,
        resetsAt: timestamp.add(const Duration(days: 3)),
        windowSeconds: 604800,
        isPrimary: false,
      ),
      if (includeModel)
        QuotaWindow(
          id: 'claude.model.opus',
          kind: QuotaWindowKind.modelWeekly,
          displayName: 'Opus',
          usedPercent: 77,
          remainingPercent: 23,
          resetsAt: null,
          windowSeconds: 604800,
          isPrimary: false,
        ),
      if (includeModel)
        const QuotaWindow(
          id: 'claude.model.fable',
          kind: QuotaWindowKind.modelWeekly,
          displayName: 'Fable',
          usedPercent: 100,
          remainingPercent: 0,
          isPrimary: false,
        ),
    ],
  );
}

ProviderFetchResult fakeSuccess(
  ProviderId provider, {
  DateTime? now,
  double remaining = 59,
  bool includeModel = false,
  CodexCredits? credits,
  ClaudeSpend? spend,
}) {
  return ProviderFetchResult.success(
    provider: provider,
    snapshot: fakeSnapshot(
      provider,
      now: now,
      remaining: remaining,
      includeModel: includeModel,
    ),
    identity: ProviderIdentity(
      accountHint: 'sample@example.com',
      plan: provider == ProviderId.codex
          ? 'Plus'
          : includeModel
          ? 'Max'
          : 'Pro',
      identityKey: '${provider.name}-identity',
    ),
    resetCredits: provider == ProviderId.codex
        ? ResetCreditsSnapshot(
            availableCount: 3,
            earliestExpiry: (now ?? DateTime(2026, 7, 29, 9)).add(
              const Duration(days: 6),
            ),
            availableCredits: [
              for (final offset in [6, 7, 8])
                ResetCreditEntry(
                  id: 'credit-$offset',
                  resetType: 'codex_rate_limits',
                  grantedAt: now ?? DateTime(2026, 7, 29, 9),
                  expiresAt: (now ?? DateTime(2026, 7, 29, 9)).add(
                    Duration(days: offset),
                  ),
                ),
            ],
          )
        : null,
    // 两者各自只属于一家 Provider，按 provider 分派，避免造出真实响应里
    // 不可能出现的组合。
    credits: provider == ProviderId.codex ? credits : null,
    spend: provider == ProviderId.claude ? spend : null,
  );
}
