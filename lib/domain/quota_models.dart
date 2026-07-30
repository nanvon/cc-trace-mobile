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

  final String? accountHint;
  final String? plan;
  final String? identityKey;

  Map<String, Object?> toJson() {
    return {
      'accountHint': accountHint,
      'plan': plan,
      'identityKey': identityKey,
    };
  }

  factory ProviderIdentity.fromJson(Map<String, Object?> json) {
    return ProviderIdentity(
      accountHint: json['accountHint'] as String?,
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
      'lastSuccessAt': lastSuccessAt?.toUtc().toIso8601String(),
    };
  }

  factory ProviderViewState.fromCacheJson(Map<String, Object?> json) {
    final provider = ProviderIdDetails.fromJson(json['provider']! as String);
    final identityJson = json['identity'] as Map<String, Object?>?;
    final snapshotJson = json['snapshot'] as Map<String, Object?>?;
    final creditsJson = json['resetCredits'] as Map<String, Object?>?;
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
      resetCredits: creditsJson == null
          ? null
          : ResetCreditsSnapshot.fromJson(creditsJson),
      lastSuccessAt: _date(json['lastSuccessAt']),
    );
  }
}

DateTime? _date(Object? value) {
  return value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
