import 'dart:math' as math;

enum ProviderId { codex, claude }

extension ProviderIdDetails on ProviderId {
  String get displayName => switch (this) {
    ProviderId.codex => 'Codex',
    ProviderId.claude => 'Claude Code',
  };

  String get storageKey => name;

  static ProviderId fromJson(String value) {
    return ProviderId.values.firstWhere((provider) => provider.name == value);
  }
}

enum RefreshState { idle, loading, refreshing }

enum SnapshotFreshness { empty, live, stale }

enum ProviderAvailability {
  ready,
  noCredentials,
  unsupported,
  offline,
  rateLimited,
  error,
}

enum ErrorKind { credentials, protocol }

enum QuotaWindowKind { fiveHour, weekly, modelWeekly, unknown }

class QuotaWindow {
  const QuotaWindow({
    required this.id,
    required this.kind,
    required this.usedPercent,
    required this.remainingPercent,
    required this.isPrimary,
    this.displayName,
    this.resetsAt,
    this.windowSeconds,
  });

  final String id;
  final QuotaWindowKind kind;
  final String? displayName;
  final double usedPercent;
  final double remainingPercent;
  final DateTime? resetsAt;
  final int? windowSeconds;
  final bool isPrimary;

  static double normalizedRemaining(double usedPercent) {
    return math.max(0, math.min(100, 100 - usedPercent)).toDouble();
  }

  QuotaWindow copyWith({
    String? id,
    QuotaWindowKind? kind,
    String? displayName,
    double? usedPercent,
    double? remainingPercent,
    DateTime? resetsAt,
    int? windowSeconds,
    bool? isPrimary,
  }) {
    return QuotaWindow(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      displayName: displayName ?? this.displayName,
      usedPercent: usedPercent ?? this.usedPercent,
      remainingPercent: remainingPercent ?? this.remainingPercent,
      resetsAt: resetsAt ?? this.resetsAt,
      windowSeconds: windowSeconds ?? this.windowSeconds,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'displayName': displayName,
      'usedPercent': usedPercent,
      'remainingPercent': remainingPercent,
      'resetsAt': resetsAt?.toUtc().toIso8601String(),
      'windowSeconds': windowSeconds,
      'isPrimary': isPrimary,
    };
  }

  factory QuotaWindow.fromJson(Map<String, Object?> json) {
    return QuotaWindow(
      id: json['id']! as String,
      kind: QuotaWindowKind.values.firstWhere(
        (kind) => kind.name == json['kind'],
      ),
      displayName: json['displayName'] as String?,
      usedPercent: (json['usedPercent']! as num).toDouble(),
      remainingPercent: (json['remainingPercent']! as num).toDouble(),
      resetsAt: _date(json['resetsAt']),
      windowSeconds: (json['windowSeconds'] as num?)?.toInt(),
      isPrimary: json['isPrimary']! as bool,
    );
  }
}

class QuotaSnapshot {
  const QuotaSnapshot({required this.windows, required this.capturedAt});

  final List<QuotaWindow> windows;
  final DateTime capturedAt;

  QuotaWindow get primary => windows.first;

  Map<String, Object?> toJson() {
    return {
      'windows': windows.map((window) => window.toJson()).toList(),
      'capturedAt': capturedAt.toUtc().toIso8601String(),
    };
  }

  factory QuotaSnapshot.fromJson(Map<String, Object?> json) {
    return QuotaSnapshot(
      windows: (json['windows']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(QuotaWindow.fromJson)
          .toList(growable: false),
      capturedAt: DateTime.parse(json['capturedAt']! as String),
    );
  }
}

class ProviderIdentity {
  const ProviderIdentity({this.accountHint, this.plan, this.identityKey});

  /// 完整邮箱只作为 UI 提示来源，属于可识别个人信息；普通额度缓存
  /// （quotaCache v2）不再序列化它，只从安全凭据恢复。
  final String? accountHint;
  final String? plan;
  final String? identityKey;

  Map<String, Object?> toJson() {
    return {
      'plan': plan,
      'identityKey': identityKey,
    };
  }

  factory ProviderIdentity.fromJson(Map<String, Object?> json) {
    return ProviderIdentity(
      plan: json['plan'] as String?,
      identityKey: json['identityKey'] as String?,
    );
  }
}

class ResetCreditEntry {
  const ResetCreditEntry({
    this.id,
    this.resetType,
    this.grantedAt,
    this.expiresAt,
  });

  final String? id;
  final String? resetType;
  final DateTime? grantedAt;
  final DateTime? expiresAt;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'resetType': resetType,
      'grantedAt': grantedAt?.toUtc().toIso8601String(),
      'expiresAt': expiresAt?.toUtc().toIso8601String(),
    };
  }

  factory ResetCreditEntry.fromJson(Map<String, Object?> json) {
    return ResetCreditEntry(
      id: json['id'] as String?,
      resetType: json['resetType'] as String?,
      grantedAt: _date(json['grantedAt']),
      expiresAt: _date(json['expiresAt']),
    );
  }
}

class ResetCreditsSnapshot {
  const ResetCreditsSnapshot({
    required this.availableCount,
    this.earliestExpiry,
    this.availableCredits = const [],
  });

  final int availableCount;
  final DateTime? earliestExpiry;
  final List<ResetCreditEntry> availableCredits;

  Map<String, Object?> toJson() {
    return {
      'availableCount': availableCount,
      'earliestExpiry': earliestExpiry?.toUtc().toIso8601String(),
      'availableCredits': availableCredits
          .map((credit) => credit.toJson())
          .toList(growable: false),
    };
  }

  factory ResetCreditsSnapshot.fromJson(Map<String, Object?> json) {
    final creditsJson = json['availableCredits'];
    final availableCredits = creditsJson is List<Object?>
        ? creditsJson
              .whereType<Map>()
              .map(
                (credit) =>
                    ResetCreditEntry.fromJson(credit.cast<String, Object?>()),
              )
              .toList(growable: false)
        : const <ResetCreditEntry>[];
    return ResetCreditsSnapshot(
      availableCount: (json['availableCount']! as num).toInt(),
      earliestExpiry: _date(json['earliestExpiry']),
      availableCredits: availableCredits,
    );
  }
}

/// Codex 的额外额度（credits），来自 `/wham/usage` 的 `credits` 对象。
///
/// **这是点数不是钱**：套餐限额用尽后靠它继续用。[balance] 保留 Provider 给的
/// 十进制字符串原样（形如 `4763.2323960000`），不在解析期转成浮点——取整与
/// 千分位属于展示决定，留给界面层做。
class CodexCredits {
  const CodexCredits({
    required this.hasCredits,
    required this.unlimited,
    required this.overageLimitReached,
    this.balance,
  });

  final bool hasCredits;
  final bool unlimited;
  final bool overageLimitReached;
  final String? balance;

  Map<String, Object?> toJson() {
    return {
      'hasCredits': hasCredits,
      'unlimited': unlimited,
      'overageLimitReached': overageLimitReached,
      'balance': balance,
    };
  }

  factory CodexCredits.fromJson(Map<String, Object?> json) {
    return CodexCredits(
      hasCredits: json['hasCredits'] as bool? ?? false,
      unlimited: json['unlimited'] as bool? ?? false,
      overageLimitReached: json['overageLimitReached'] as bool? ?? false,
      balance: json['balance'] as String?,
    );
  }
}

/// Provider 用最小货币单位表达的金额：[amountMinor] 除以 10 的 [exponent] 次方
/// 才是面值。不预先算成浮点，理由同 [CodexCredits.balance]。
class MoneyAmount {
  const MoneyAmount({
    required this.amountMinor,
    required this.currency,
    required this.exponent,
  });

  final int amountMinor;
  final String currency;
  final int exponent;

  Map<String, Object?> toJson() {
    return {
      'amountMinor': amountMinor,
      'currency': currency,
      'exponent': exponent,
    };
  }

  factory MoneyAmount.fromJson(Map<String, Object?> json) {
    return MoneyAmount(
      amountMinor: (json['amountMinor']! as num).toInt(),
      currency: json['currency']! as String,
      exponent: (json['exponent']! as num).toInt(),
    );
  }
}

/// Claude 订阅额度用尽后按 API 价继续用的月度花费，来自 `/api/oauth/usage` 的 `spend`。
///
/// **这不是账户余额。** 同一对象里的 `balance` 与 `auto_reload` 在 OAuth 链路上
/// 恒为 `null`（2026-08-30 实测，见 `docs/移动端额度展示要求.md` §4.3），账户余额
/// 只在 claude.ai 网页可见；那走的是另一套鉴权，移动端拿不到也不去拿。
class ClaudeSpend {
  const ClaudeSpend({
    required this.enabled,
    this.used,
    this.limit,
    this.percent,
  });

  final bool enabled;
  final MoneyAmount? used;
  final MoneyAmount? limit;
  final double? percent;

  /// 只有金额齐备才值得占一行；缺任何一半都不展示，不补造数据。
  bool get hasAmounts => used != null && limit != null;

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'used': used?.toJson(),
      'limit': limit?.toJson(),
      'percent': percent,
    };
  }

  factory ClaudeSpend.fromJson(Map<String, Object?> json) {
    final used = json['used'] as Map<String, Object?>?;
    final limit = json['limit'] as Map<String, Object?>?;
    return ClaudeSpend(
      enabled: json['enabled'] as bool? ?? false,
      used: used == null ? null : MoneyAmount.fromJson(used),
      limit: limit == null ? null : MoneyAmount.fromJson(limit),
      percent: (json['percent'] as num?)?.toDouble(),
    );
  }
}

class ProviderViewState {
  const ProviderViewState({
    required this.provider,
    required this.refresh,
    required this.freshness,
    required this.availability,
    required this.isSignedIn,
    this.identity,
    this.snapshot,
    this.resetCredits,
    this.credits,
    this.spend,
    this.lastSuccessAt,
    this.lastAttemptAt,
    this.retryAfter,
    this.errorKind,
  });

  factory ProviderViewState.initial(ProviderId provider) {
    return ProviderViewState(
      provider: provider,
      refresh: RefreshState.idle,
      freshness: SnapshotFreshness.empty,
      availability: ProviderAvailability.noCredentials,
      isSignedIn: false,
    );
  }

  final ProviderId provider;
  final RefreshState refresh;
  final SnapshotFreshness freshness;
  final ProviderAvailability availability;
  final bool isSignedIn;
  final ProviderIdentity? identity;
  final QuotaSnapshot? snapshot;
  final ResetCreditsSnapshot? resetCredits;
  final CodexCredits? credits;
  final ClaudeSpend? spend;
  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;
  final DateTime? retryAfter;
  final ErrorKind? errorKind;

  bool get hasSnapshot => snapshot != null && snapshot!.windows.isNotEmpty;

  ProviderViewState copyWith({
    RefreshState? refresh,
    SnapshotFreshness? freshness,
    ProviderAvailability? availability,
    bool? isSignedIn,
    ProviderIdentity? identity,
    bool clearIdentity = false,
    QuotaSnapshot? snapshot,
    bool clearSnapshot = false,
    ResetCreditsSnapshot? resetCredits,
    bool clearResetCredits = false,
    CodexCredits? credits,
    bool clearCredits = false,
    ClaudeSpend? spend,
    bool clearSpend = false,
    DateTime? lastSuccessAt,
    DateTime? lastAttemptAt,
    DateTime? retryAfter,
    bool clearRetryAfter = false,
    ErrorKind? errorKind,
    bool clearError = false,
  }) {
    return ProviderViewState(
      provider: provider,
      refresh: refresh ?? this.refresh,
      freshness: freshness ?? this.freshness,
      availability: availability ?? this.availability,
      isSignedIn: isSignedIn ?? this.isSignedIn,
      identity: clearIdentity ? null : identity ?? this.identity,
      snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
      resetCredits: clearResetCredits
          ? null
          : resetCredits ?? this.resetCredits,
      credits: clearCredits ? null : credits ?? this.credits,
      spend: clearSpend ? null : spend ?? this.spend,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      retryAfter: clearRetryAfter ? null : retryAfter ?? this.retryAfter,
      errorKind: clearError ? null : errorKind ?? this.errorKind,
    );
  }

  Map<String, Object?> toCacheJson() {
    return {
      'provider': provider.name,
      'identity': identity?.toJson(),
      'snapshot': snapshot?.toJson(),
      'resetCredits': resetCredits?.toJson(),
      'credits': credits?.toJson(),
      'spend': spend?.toJson(),
      'lastSuccessAt': lastSuccessAt?.toUtc().toIso8601String(),
    };
  }

  factory ProviderViewState.fromCacheJson(Map<String, Object?> json) {
    final provider = ProviderIdDetails.fromJson(json['provider']! as String);
    final identityJson = json['identity'] as Map<String, Object?>?;
    final snapshotJson = json['snapshot'] as Map<String, Object?>?;
    final resetCreditsJson = json['resetCredits'] as Map<String, Object?>?;
    final creditsJson = json['credits'] as Map<String, Object?>?;
    final spendJson = json['spend'] as Map<String, Object?>?;
    return ProviderViewState(
      provider: provider,
      refresh: RefreshState.idle,
      freshness: SnapshotFreshness.stale,
      availability: ProviderAvailability.ready,
      isSignedIn: true,
      identity: identityJson == null
          ? null
          : ProviderIdentity.fromJson(identityJson),
      snapshot: snapshotJson == null
          ? null
          : QuotaSnapshot.fromJson(snapshotJson),
      resetCredits: resetCreditsJson == null
          ? null
          : ResetCreditsSnapshot.fromJson(resetCreditsJson),
      credits: creditsJson == null ? null : CodexCredits.fromJson(creditsJson),
      spend: spendJson == null ? null : ClaudeSpend.fromJson(spendJson),
      lastSuccessAt: _date(json['lastSuccessAt']),
    );
  }
}

DateTime? _date(Object? value) {
  return value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
