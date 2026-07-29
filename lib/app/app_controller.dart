// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../auth/oauth_coordinator.dart';
import '../auth/token_bundle.dart';
import '../domain/app_settings.dart';
import '../domain/quota_models.dart';
import '../providers/provider_api.dart';
import '../storage/credentials_store.dart';
import '../storage/local_store.dart';

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({
    required CredentialsStore credentials,
    required LocalStore localStore,
    required OAuthGateway oauth,
    required ProviderGateway providerApi,
    DateTime Function()? now,
  }) : _credentials = credentials,
       _localStore = localStore,
       _oauth = oauth,
       _providerApi = providerApi,
       _now = now ?? DateTime.now,
       _providers = {
         for (final provider in ProviderId.values)
           provider: ProviderViewState.initial(provider),
       };

  final CredentialsStore _credentials;
  final LocalStore _localStore;
  final OAuthGateway _oauth;
  final ProviderGateway _providerApi;
  final DateTime Function() _now;
  final Map<ProviderId, ProviderViewState> _providers;
  final Map<ProviderId, _RefreshFlight> _refreshing = {};
  final Map<ProviderId, int> _authGenerations = {};
  final Set<ProviderId> _credentialRefreshBlocked = {};
  final Map<ProviderId, DateTime> _providerHeldUntil = {};
  final Map<ProviderId, int> _rateFailures = {};
  final Map<ProviderId, int> _transientFailures = {};
  Future<void> _cacheMutations = Future<void>.value();

  AppSettings _settings = const AppSettings();
  bool _initialized = false;
  bool _foreground = true;
  ProviderId? _authorizing;
  DateTime? _lastManualRefresh;
  String? _notice;
  Timer? _scheduleTimer;
  Timer? _noticeTimer;

  AppSettings get settings => _settings;
  bool get initialized => _initialized;
  ProviderId? get authorizing => _authorizing;
  String? get notice => _notice;
  DateTime get now => _now();
  Iterable<ProviderViewState> get providers => _providers.values;
  ProviderViewState provider(ProviderId id) => _providers[id]!;
  bool get allSignedOut =>
      _providers.values.every((state) => !state.isSignedIn);
  bool get isRefreshing => _providers.values.any(
    (state) =>
        state.refresh == RefreshState.loading ||
        state.refresh == RefreshState.refreshing,
  );

  Future<void> bootstrap() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      await _bootstrap();
    } on Object {
      _initialized = true;
      _notice = '无法读取本机存储，请重启应用';
      notifyListeners();
    }
  }

  Future<void> _bootstrap() async {
    await _localStore.prepareInstall(_credentials);
    _settings = await _localStore.readSettings();
    final cached = {
      for (final state in await _localStore.readQuotaCache())
        state.provider: state,
    };

    for (final provider in ProviderId.values) {
      final token = await _credentials.read(provider);
      final previous = cached[provider];
      if (token == null) {
        _providers[provider] = ProviderViewState.initial(provider);
        if (previous != null) {
          await _localStore.removeProviderCache(provider);
        }
        continue;
      }
      final tokenIdentity = token.identityKey;
      final cachedIdentity = previous?.identity?.identityKey;
      if (previous != null &&
          tokenIdentity != null &&
          cachedIdentity != null &&
          tokenIdentity != cachedIdentity) {
        await _localStore.removeProviderCache(provider);
        _providers[provider] = _emptySignedIn(provider, token);
      } else if (previous != null) {
        final isCurrent =
            previous.lastSuccessAt != null &&
            _now().isBefore(
              previous.lastSuccessAt!.add(_settings.refreshInterval.duration),
            );
        _providers[provider] = previous.copyWith(
          isSignedIn: true,
          freshness: isCurrent
              ? SnapshotFreshness.live
              : SnapshotFreshness.stale,
          availability: ProviderAvailability.ready,
          identity: ProviderIdentity(
            accountHint: token.accountHint ?? previous.identity?.accountHint,
            plan: previous.identity?.plan,
            identityKey: tokenIdentity ?? cachedIdentity,
          ),
        );
      } else {
        _providers[provider] = _emptySignedIn(provider, token);
      }
    }

    _initialized = true;
    _restartSchedule();
    notifyListeners();

    await Future.wait(
      ProviderId.values
          .where(_isDue)
          .map((provider) => refreshProvider(provider)),
    );
  }

  ProviderViewState _emptySignedIn(ProviderId provider, TokenBundle token) {
    return ProviderViewState(
      provider: provider,
      refresh: RefreshState.idle,
      freshness: SnapshotFreshness.empty,
      availability: ProviderAvailability.ready,
      isSignedIn: true,
      identity: ProviderIdentity(
        accountHint: token.accountHint,
        identityKey: token.identityKey,
      ),
    );
  }

  int _authGeneration(ProviderId provider) => _authGenerations[provider] ?? 0;

  int _advanceAuthGeneration(ProviderId provider) {
    final next = _authGeneration(provider) + 1;
    _authGenerations[provider] = next;
    return next;
  }

  bool _isCurrentAuthGeneration(ProviderId provider, int generation) {
    return _authGeneration(provider) == generation;
  }

  Future<T> _mutateCache<T>(Future<T> Function() operation) async {
    final previous = _cacheMutations;
    final completed = Completer<void>();
    _cacheMutations = completed.future;
    await previous;
    try {
      return await operation();
    } finally {
      completed.complete();
    }
  }

  Future<void> _writeQuotaCacheIfCurrent(ProviderId provider, int generation) {
    return _mutateCache(() async {
      if (!_isCurrentAuthGeneration(provider, generation)) {
        return;
      }
      await _localStore.writeQuotaCache(_providers.values);
    });
  }

  Future<void> _removeProviderCache(ProviderId provider) {
    return _mutateCache(() => _localStore.removeProviderCache(provider));
  }

  bool _isDue(ProviderId provider) {
    final state = _providers[provider]!;
    if (!state.isSignedIn || _credentialRefreshBlocked.contains(provider)) {
      return false;
    }
    final last = state.lastSuccessAt;
    return last == null ||
        !_now().isBefore(last.add(_settings.refreshInterval.duration));
  }

  Future<void> refreshAll({bool manual = false}) async {
    if (!_initialized) {
      return;
    }
    final now = _now();
    if (manual) {
      final next = _lastManualRefresh?.add(const Duration(minutes: 1));
      if (next != null && now.isBefore(next)) {
        _showHeldNotice(next);
        return;
      }
      _lastManualRefresh = now;
    }

    final signedIn = ProviderId.values.where(
      (provider) => _providers[provider]!.isSignedIn,
    );
    if (signedIn.isEmpty) {
      return;
    }
    final eligible = signedIn
        .where((provider) => !_credentialRefreshBlocked.contains(provider))
        .toList(growable: false);
    if (eligible.isEmpty) {
      return;
    }
    final runnable = eligible
        .where((provider) {
          final held = _providerHeldUntil[provider];
          return held == null || !now.isBefore(held);
        })
        .toList(growable: false);
    if (runnable.isEmpty) {
      final earliest = eligible
          .map((provider) => _providerHeldUntil[provider])
          .whereType<DateTime>()
          .reduce((left, right) => left.isBefore(right) ? left : right);
      _showHeldNotice(earliest);
      return;
    }
    await Future.wait(runnable.map((provider) => refreshProvider(provider)));
  }

  Future<void> refreshProvider(ProviderId provider) {
    if (_credentialRefreshBlocked.contains(provider)) {
      return Future<void>.value();
    }
    final generation = _authGeneration(provider);
    final active = _refreshing[provider];
    if (active != null && active.generation == generation) {
      return active.future;
    }

    late final _RefreshFlight refresh;
    final future = () async {
      try {
        await _performRefresh(provider, generation);
      } finally {
        if (identical(_refreshing[provider], refresh)) {
          _refreshing.remove(provider);
        }
      }
    }();
    refresh = _RefreshFlight(generation: generation, future: future);
    _refreshing[provider] = refresh;
    return future;
  }

  Future<void> _performRefresh(ProviderId provider, int generation) async {
    if (!_isCurrentAuthGeneration(provider, generation)) {
      return;
    }
    final before = _providers[provider]!;
    if (!before.isSignedIn) {
      return;
    }
    final held = _providerHeldUntil[provider];
    if (held != null && _now().isBefore(held)) {
      _showHeldNotice(held);
      return;
    }

    _providers[provider] = before.copyWith(
      refresh: before.hasSnapshot
          ? RefreshState.refreshing
          : RefreshState.loading,
      lastAttemptAt: _now(),
      clearRetryAfter: true,
      clearError: true,
    );
    notifyListeners();

    late final ProviderFetchResult result;
    try {
      result = await _providerApi.fetch(provider);
    } on Object {
      result = ProviderFetchResult.failure(
        provider: provider,
        failure: ProviderFetchFailureKind.protocol,
      );
    }
    if (!_isCurrentAuthGeneration(provider, generation)) {
      return;
    }
    if (result.failure == ProviderFetchFailureKind.superseded) {
      _providers[provider] = before.copyWith(refresh: RefreshState.idle);
      notifyListeners();
      return;
    }
    if (result.isSuccess) {
      final current = _providers[provider]!;
      final oldIdentity = current.identity?.identityKey;
      final newIdentity = result.identity?.identityKey;
      final identityChanged =
          oldIdentity != null &&
          newIdentity != null &&
          oldIdentity != newIdentity;
      final snapshot = identityChanged
          ? result.snapshot!
          : _preserveFutureResets(current.snapshot, result.snapshot!);
      final hasKnownWindow = snapshot.windows.any(
        (window) => window.kind != QuotaWindowKind.unknown,
      );
      _providers[provider] = ProviderViewState(
        provider: provider,
        refresh: RefreshState.idle,
        freshness: SnapshotFreshness.live,
        availability: hasKnownWindow
            ? ProviderAvailability.ready
            : ProviderAvailability.unsupported,
        isSignedIn: true,
        identity: result.identity,
        snapshot: snapshot,
        resetCredits: result.resetCredits,
        lastSuccessAt: _now(),
        lastAttemptAt: current.lastAttemptAt,
      );
      _providerHeldUntil.remove(provider);
      _credentialRefreshBlocked.remove(provider);
      _rateFailures.remove(provider);
      _transientFailures.remove(provider);
      _clearNotice();
      await _writeQuotaCacheIfCurrent(provider, generation);
      if (!_isCurrentAuthGeneration(provider, generation)) {
        return;
      }
      notifyListeners();
      return;
    }

    await _applyFailure(provider, result, generation);
  }

  QuotaSnapshot _preserveFutureResets(
    QuotaSnapshot? previous,
    QuotaSnapshot next,
  ) {
    if (previous == null) {
      return next;
    }
    final oldWindows = {
      for (final window in previous.windows) window.id: window,
    };
    final now = _now();
    return QuotaSnapshot(
      capturedAt: next.capturedAt,
      windows: next.windows
          .map((window) {
            if (window.resetsAt != null) {
              return window;
            }
            final old = oldWindows[window.id];
            if (old != null &&
                old.kind == window.kind &&
                old.resetsAt != null &&
                old.resetsAt!.isAfter(now)) {
              return window.copyWith(resetsAt: old.resetsAt);
            }
            return window;
          })
          .toList(growable: false),
    );
  }

  Future<void> _applyFailure(
    ProviderId provider,
    ProviderFetchResult result,
    int generation,
  ) async {
    if (!_isCurrentAuthGeneration(provider, generation)) {
      return;
    }
    final current = _providers[provider]!;
    final failure = result.failure!;
    if (failure == ProviderFetchFailureKind.noCredentials) {
      _providers[provider] = ProviderViewState.initial(provider);
      await _removeProviderCache(provider);
      if (!_isCurrentAuthGeneration(provider, generation)) {
        return;
      }
      notifyListeners();
      return;
    }

    final availability = switch (failure) {
      ProviderFetchFailureKind.credentials => ProviderAvailability.error,
      ProviderFetchFailureKind.rateLimited => ProviderAvailability.rateLimited,
      ProviderFetchFailureKind.offline => ProviderAvailability.offline,
      ProviderFetchFailureKind.protocol => ProviderAvailability.error,
      ProviderFetchFailureKind.superseded => ProviderAvailability.error,
      ProviderFetchFailureKind.noCredentials =>
        ProviderAvailability.noCredentials,
    };
    final errorKind = switch (failure) {
      ProviderFetchFailureKind.credentials => ErrorKind.credentials,
      ProviderFetchFailureKind.protocol => ErrorKind.protocol,
      _ => null,
    };
    if (failure == ProviderFetchFailureKind.credentials) {
      _credentialRefreshBlocked.add(provider);
    }
    final delay = _retryDelay(provider, failure, result.retryAfter);
    final retryAt = delay == null ? null : _now().add(delay);
    if (retryAt != null) {
      _providerHeldUntil[provider] = retryAt;
    }
    _providers[provider] = current.copyWith(
      refresh: RefreshState.idle,
      freshness: current.hasSnapshot
          ? SnapshotFreshness.stale
          : SnapshotFreshness.empty,
      availability: availability,
      retryAfter: retryAt,
      clearRetryAfter: retryAt == null,
      errorKind: errorKind,
      clearError: errorKind == null,
      clearResetCredits: provider == ProviderId.codex,
    );
    notifyListeners();
  }

  Duration? _retryDelay(
    ProviderId provider,
    ProviderFetchFailureKind failure,
    Duration? serverDelay,
  ) {
    if (failure == ProviderFetchFailureKind.credentials ||
        failure == ProviderFetchFailureKind.superseded) {
      return null;
    }
    if (failure == ProviderFetchFailureKind.rateLimited) {
      final attempt = (_rateFailures[provider] ?? 0) + 1;
      _rateFailures[provider] = attempt;
      const seconds = [60, 120, 300, 900];
      final index = (attempt - 1).clamp(0, seconds.length - 1).toInt();
      final fallback = Duration(seconds: seconds[index]);
      final chosen = serverDelay == null || serverDelay < fallback
          ? fallback
          : serverDelay;
      return chosen;
    }
    final attempt = (_transientFailures[provider] ?? 0) + 1;
    _transientFailures[provider] = attempt;
    const seconds = [30, 60, 120, 300];
    final index = (attempt - 1).clamp(0, seconds.length - 1).toInt();
    return Duration(seconds: seconds[index]);
  }

  Future<void> signIn(ProviderId provider) async {
    if (_authorizing != null) {
      return;
    }
    final generation = _advanceAuthGeneration(provider);
    _authorizing = provider;
    _clearNotice();
    notifyListeners();
    try {
      final bundle = await _oauth.signIn(provider);
      if (!_isCurrentAuthGeneration(provider, generation)) {
        return;
      }
      try {
        await _credentials.write(bundle);
      } on Object {
        throw const OAuthFailure(OAuthFailureKind.secureStorage);
      }
      if (!_isCurrentAuthGeneration(provider, generation)) {
        await _credentials.delete(provider);
        return;
      }
      // Claude's opaque token may not expose a stable identity key. A completed
      // OAuth flow is therefore always treated as a new session: retaining an
      // old snapshot would risk showing another account's quota as stale data.
      await _removeProviderCache(provider);
      if (!_isCurrentAuthGeneration(provider, generation)) {
        return;
      }
      _providers[provider] = _emptySignedIn(provider, bundle);
      _providerHeldUntil.remove(provider);
      _credentialRefreshBlocked.remove(provider);
      _rateFailures.remove(provider);
      _transientFailures.remove(provider);
      notifyListeners();
      await refreshProvider(provider);
    } on OAuthFailure catch (failure) {
      if (!_isCurrentAuthGeneration(provider, generation)) {
        return;
      }
      _notice = _oauthFailureMessage(provider, failure.kind);
      _scheduleNoticeClear();
      notifyListeners();
    } on Object {
      if (!_isCurrentAuthGeneration(provider, generation)) {
        return;
      }
      _notice = '${provider.displayName} 登录未完成，请重试';
      _scheduleNoticeClear();
      notifyListeners();
    } finally {
      if (_authorizing == provider) {
        _authorizing = null;
        notifyListeners();
      }
    }
  }

  String _oauthFailureMessage(ProviderId provider, OAuthFailureKind failure) {
    final name = provider.displayName;
    return switch (failure) {
      OAuthFailureKind.cancelled => '已取消 $name 登录',
      OAuthFailureKind.timeout => '$name 登录超时，请重试',
      OAuthFailureKind.portUnavailable =>
        provider == ProviderId.codex
            ? 'Codex 登录端口 1455 和 1457 都被占用'
            : 'Claude Code 登录端口被占用',
      OAuthFailureKind.browserUnavailable => '无法打开系统浏览器',
      OAuthFailureKind.tokenExchange => '$name 登录交换凭据失败',
      OAuthFailureKind.invalidResponse => '$name 返回了无法识别的登录结果',
      OAuthFailureKind.secureStorage => '无法安全保存 $name 登录凭据',
    };
  }

  Future<void> signOut(ProviderId provider) async {
    final generation = _advanceAuthGeneration(provider);
    await _credentials.delete(provider);
    await _removeProviderCache(provider);
    if (!_isCurrentAuthGeneration(provider, generation)) {
      return;
    }
    _providerHeldUntil.remove(provider);
    _credentialRefreshBlocked.remove(provider);
    _rateFailures.remove(provider);
    _transientFailures.remove(provider);
    _providers[provider] = ProviderViewState.initial(provider);
    notifyListeners();
  }

  Future<void> setAppearance(AppearancePreference appearance) async {
    _settings = _settings.copyWith(appearance: appearance);
    await _localStore.writeSettings(_settings);
    notifyListeners();
  }

  Future<void> setRefreshInterval(RefreshInterval interval) async {
    _settings = _settings.copyWith(refreshInterval: interval);
    await _localStore.writeSettings(_settings);
    _restartSchedule();
    notifyListeners();
  }

  void _restartSchedule() {
    _scheduleTimer?.cancel();
    if (!_foreground) {
      return;
    }
    _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_foreground) {
        final due = ProviderId.values.where(_isDue);
        for (final provider in due) {
          unawaited(refreshProvider(provider));
        }
      }
    });
  }

  void _showHeldNotice(DateTime until) {
    final seconds = until
        .difference(_now())
        .inSeconds
        .clamp(1, 2147483647)
        .toInt();
    final minutes = (seconds / 60).ceil();
    _notice = minutes <= 1 ? '刚刷新过，1 分钟后可再试' : '刷新暂缓，约 $minutes 分钟后可再试';
    _scheduleNoticeClear(until: until);
    notifyListeners();
  }

  void _scheduleNoticeClear({DateTime? until}) {
    _noticeTimer?.cancel();
    final delay = until?.difference(_now()) ?? const Duration(seconds: 4);
    _noticeTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _notice = null;
      notifyListeners();
    });
  }

  void _clearNotice() {
    _noticeTimer?.cancel();
    _notice = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _restartSchedule();
      final due = ProviderId.values.where(_isDue);
      for (final provider in due) {
        unawaited(refreshProvider(provider));
      }
    } else {
      _scheduleTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scheduleTimer?.cancel();
    _noticeTimer?.cancel();
    _oauth.dispose();
    if (_providerApi case final ProviderApi api) {
      api.dispose();
    }
    super.dispose();
  }
}

class _RefreshFlight {
  const _RefreshFlight({required this.generation, required this.future});

  final int generation;
  final Future<void> future;
}
