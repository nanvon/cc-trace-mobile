import 'dart:convert';

import '../domain/quota_models.dart';

class ParsedUsage {
  const ParsedUsage({
    required this.snapshot,
    this.identity,
    this.credits,
    this.spend,
  });

  final QuotaSnapshot snapshot;
  final ProviderIdentity? identity;

  /// Codex 专有；Claude 恒为 null。
  final CodexCredits? credits;

  /// Claude 专有；Codex 恒为 null。
  final ClaudeSpend? spend;
}

class UsageParseException implements Exception {
  const UsageParseException();

  @override
  String toString() => 'UsageParseException(<response redacted>)';
}

ParsedUsage parseCodexUsage(String input, DateTime capturedAt) {
  final root = _object(jsonDecode(input));
  final rateLimit = _object(root['rate_limit']);
  final primary = _object(rateLimit['primary_window']);
  final windows = <QuotaWindow>[
    _codexWindow(primary, capturedAt),
    if (rateLimit['secondary_window'] is Map)
      _codexWindow(_object(rateLimit['secondary_window']), capturedAt),
  ];

  final marked = [windows.first.copyWith(isPrimary: true), ...windows.skip(1)];
  final plan = _text(root['plan_type']);
  return ParsedUsage(
    snapshot: QuotaSnapshot(windows: marked, capturedAt: capturedAt),
    identity: plan == null ? null : ProviderIdentity(plan: _titleCase(plan)),
    credits: _codexCredits(root['credits']),
  );
}

/// `credits` 缺失或结构异常时返回 null——额外额度不是主额度，
/// 不能因为它把整份 usage 判成解析失败。
CodexCredits? _codexCredits(Object? value) {
  if (value is! Map) {
    return null;
  }
  final row = value.cast<String, Object?>();
  final balance = row['balance'];
  return CodexCredits(
    hasCredits: row['has_credits'] == true,
    unlimited: row['unlimited'] == true,
    overageLimitReached: row['overage_limit_reached'] == true,
    // Provider 给的是十进制字符串；数字形态也接受，但不做四舍五入。
    balance: switch (balance) {
      final String text when text.trim().isNotEmpty => text.trim(),
      final num number when number.isFinite => number.toString(),
      _ => null,
    },
  );
}

QuotaWindow _codexWindow(Map<String, Object?> raw, DateTime capturedAt) {
  final used = _finite(raw['used_percent']);
  final seconds = _optionalInteger(raw['limit_window_seconds']);
  final kind = switch (seconds) {
    18000 => QuotaWindowKind.fiveHour,
    604800 => QuotaWindowKind.weekly,
    _ => QuotaWindowKind.unknown,
  };
  final id = switch (kind) {
    QuotaWindowKind.fiveHour => 'codex.five-hour',
    QuotaWindowKind.weekly => 'codex.weekly',
    _ => 'codex.unknown-${seconds ?? 'unspecified'}',
  };
  return QuotaWindow(
    id: id,
    kind: kind,
    usedPercent: used,
    remainingPercent: QuotaWindow.normalizedRemaining(used),
    resetsAt: _codexReset(raw, capturedAt),
    windowSeconds: seconds,
    isPrimary: false,
  );
}

DateTime? _codexReset(Map<String, Object?> raw, DateTime capturedAt) {
  final epoch = _optionalFinite(raw['reset_at']);
  if (epoch != null) {
    return DateTime.fromMillisecondsSinceEpoch(
      (epoch * 1000).round(),
      isUtc: true,
    ).toLocal();
  }
  final after = _optionalFinite(raw['reset_after_seconds']);
  return after == null
      ? null
      : capturedAt.add(Duration(milliseconds: (after * 1000).round()));
}

ParsedUsage parseClaudeUsage(String input, DateTime capturedAt) {
  final root = _object(jsonDecode(input));
  QuotaWindow? session;
  QuotaWindow? weekly;
  final models = <QuotaWindow>[];
  final unknown = <QuotaWindow>[];

  final limits = root['limits'];
  if (limits is List<Object?>) {
    for (final value in limits.whereType<Map>()) {
      final row = value.cast<String, Object?>();
      final kind = _text(row['kind']);
      if (kind == null) {
        throw const UsageParseException();
      }
      final used = _finite(row['percent']);
      final reset = _dateValue(row['resets_at']);
      switch (kind) {
        case 'session':
          session = _window(
            id: 'claude.five-hour',
            kind: QuotaWindowKind.fiveHour,
            used: used,
            reset: reset,
            seconds: 18000,
          );
        case 'weekly_all':
          weekly = _window(
            id: 'claude.weekly',
            kind: QuotaWindowKind.weekly,
            used: used,
            reset: reset,
            seconds: 604800,
          );
        case 'weekly_scoped':
          final identity = _scopeIdentity(row['scope']);
          final slug = _slug(identity.$1 ?? identity.$2);
          final candidate = _window(
            id: 'claude.model.${slug.isEmpty ? models.length : slug}',
            kind: QuotaWindowKind.modelWeekly,
            used: used,
            reset: reset,
            seconds: 604800,
            displayName: identity.$2,
          );
          _upsert(models, candidate);
        default:
          _upsert(
            unknown,
            _window(
              id: 'claude.unknown.${_slug(kind)}',
              kind: QuotaWindowKind.unknown,
              used: used,
              reset: reset,
            ),
          );
      }
    }
  }

  final legacySession = _legacy(
    root['five_hour'],
    id: 'claude.five-hour',
    kind: QuotaWindowKind.fiveHour,
    seconds: 18000,
  );
  final legacyWeekly = _legacy(
    root['seven_day'],
    id: 'claude.weekly',
    kind: QuotaWindowKind.weekly,
    seconds: 604800,
  );
  session = _merge(session, legacySession);
  weekly = _merge(weekly, legacyWeekly);
  _appendLegacyModel(
    models,
    'Opus',
    _legacy(
      root['seven_day_opus'],
      id: 'claude.model.opus',
      kind: QuotaWindowKind.modelWeekly,
      seconds: 604800,
      displayName: 'Opus',
    ),
  );
  _appendLegacyModel(
    models,
    'Sonnet',
    _legacy(
      root['seven_day_sonnet'],
      id: 'claude.model.sonnet',
      kind: QuotaWindowKind.modelWeekly,
      seconds: 604800,
      displayName: 'Sonnet',
    ),
  );

  final windows = <QuotaWindow>[?session, ?weekly, ...models, ...unknown];
  if (windows.isEmpty) {
    throw const UsageParseException();
  }
  windows[0] = windows[0].copyWith(isPrimary: true);
  // Claude 的套餐名实际来自 `/api/oauth/profile` 的 `organization.organization_type`
  // （见 `docs/移动端额度展示要求.md` §8.1）。这里保留 usage 顶层的两个键只是兜底：
  // 真实响应里没见过它们。不再试 `rate_limit_tier`——那不是套餐名，
  // 取值形如 `default_claude_max_20x`，官方客户端也把它当成独立概念。
  final plan =
      _text(root['subscriptionType']) ?? _text(root['subscription_type']);
  return ParsedUsage(
    snapshot: QuotaSnapshot(windows: windows, capturedAt: capturedAt),
    identity: plan == null ? null : ProviderIdentity(plan: _titleCase(plan)),
    spend: _claudeSpend(root['spend']),
  );
}

/// 只读 `spend`，不从 `extra_usage` 兜底。
///
/// 2026-08-30 的真实响应里两者数值一致，但 `spend` 结构更完整（自带 currency 与
/// exponent），而 `extra_usage` 的 `monthly_limit` / `used_credits` 没有显式单位。
/// 在没有验证过「只有 extra_usage 没有 spend」这种账户形态之前，不为它写兜底分支。
ClaudeSpend? _claudeSpend(Object? value) {
  if (value is! Map) {
    return null;
  }
  final row = value.cast<String, Object?>();
  final percent = row['percent'];
  return ClaudeSpend(
    enabled: row['enabled'] == true,
    used: _money(row['used']),
    limit: _money(row['limit']),
    // 这里刻意不用 _optionalFinite：它对非数字会抛，而附属信息不该拖垮主额度。
    percent: percent is num && percent.isFinite ? percent.toDouble() : null,
  );
}

MoneyAmount? _money(Object? value) {
  if (value is! Map) {
    return null;
  }
  final row = value.cast<String, Object?>();
  final minor = _optionalInteger(row['amount_minor']);
  final currency = _text(row['currency']);
  final exponent = _optionalInteger(row['exponent']);
  if (minor == null || currency == null || exponent == null || exponent < 0) {
    return null;
  }
  return MoneyAmount(
    amountMinor: minor,
    currency: currency,
    exponent: exponent,
  );
}

ResetCreditsSnapshot parseResetCredits(String input) {
  final root = _object(jsonDecode(input));
  final reportedAvailable =
      _optionalInteger(root['available_count']) ??
      _optionalInteger(root['availableCount']);
  final credits = root['credits'];
  final availableCredits = <ResetCreditEntry>[];
  DateTime? earliest;
  if (credits is List<Object?>) {
    for (final value in credits.whereType<Map>()) {
      final row = value.cast<String, Object?>();
      final status = _text(row['status'])?.toLowerCase();
      if (status != null && status != 'available') {
        continue;
      }
      final expiry = _dateValue(row['expires_at'] ?? row['expiresAt']);
      availableCredits.add(
        ResetCreditEntry(
          id: _text(row['id']),
          resetType: _text(row['reset_type'] ?? row['resetType']),
          grantedAt: _dateValue(row['granted_at'] ?? row['grantedAt']),
          expiresAt: expiry,
        ),
      );
      if (expiry != null && (earliest == null || expiry.isBefore(earliest))) {
        earliest = expiry;
      }
    }
  }
  availableCredits.sort((left, right) {
    final leftExpiry = left.expiresAt;
    final rightExpiry = right.expiresAt;
    if (leftExpiry == null) {
      return rightExpiry == null ? 0 : 1;
    }
    if (rightExpiry == null) {
      return -1;
    }
    return leftExpiry.compareTo(rightExpiry);
  });
  return ResetCreditsSnapshot(
    availableCount: reportedAvailable ?? availableCredits.length,
    earliestExpiry: earliest,
    availableCredits: availableCredits,
  );
}

QuotaWindow _window({
  required String id,
  required QuotaWindowKind kind,
  required double used,
  required DateTime? reset,
  int? seconds,
  String? displayName,
}) {
  return QuotaWindow(
    id: id,
    kind: kind,
    displayName: displayName,
    usedPercent: used,
    remainingPercent: QuotaWindow.normalizedRemaining(used),
    resetsAt: reset,
    windowSeconds: seconds,
    isPrimary: false,
  );
}

QuotaWindow? _legacy(
  Object? value, {
  required String id,
  required QuotaWindowKind kind,
  required int seconds,
  String? displayName,
}) {
  if (value == null) {
    return null;
  }
  final row = _object(value);
  return _window(
    id: id,
    kind: kind,
    used: _finite(row['utilization']),
    reset: _dateValue(row['resets_at']),
    seconds: seconds,
    displayName: displayName,
  );
}

QuotaWindow? _merge(QuotaWindow? preferred, QuotaWindow? fallback) {
  if (preferred == null) {
    return fallback;
  }
  return preferred.resetsAt == null && fallback?.resetsAt != null
      ? preferred.copyWith(resetsAt: fallback!.resetsAt)
      : preferred;
}

void _appendLegacyModel(
  List<QuotaWindow> models,
  String name,
  QuotaWindow? legacy,
) {
  if (legacy == null) {
    return;
  }
  final index = models.indexWhere(
    (window) =>
        window.id.toLowerCase().contains(name.toLowerCase()) ||
        (window.displayName?.toLowerCase().contains(name.toLowerCase()) ??
            false),
  );
  if (index < 0) {
    models.add(legacy);
  } else if (models[index].resetsAt == null && legacy.resetsAt != null) {
    models[index] = models[index].copyWith(resetsAt: legacy.resetsAt);
  }
}

(String?, String) _scopeIdentity(Object? value) {
  final scope = _object(value);
  for (final key in ['model', 'surface']) {
    final candidate = scope[key];
    if (candidate is String && candidate.trim().isNotEmpty) {
      return (null, candidate.trim());
    }
    if (candidate is Map) {
      final row = candidate.cast<String, Object?>();
      final name = _text(row['display_name']) ?? _text(row['name']);
      if (name != null) {
        return (_text(row['id']), name);
      }
    }
  }
  throw const UsageParseException();
}

void _upsert(List<QuotaWindow> windows, QuotaWindow candidate) {
  final index = windows.indexWhere((window) => window.id == candidate.id);
  if (index < 0) {
    windows.add(candidate);
  } else {
    windows[index] = candidate;
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  throw const UsageParseException();
}

double _finite(Object? value) {
  final result = value is num ? value.toDouble() : double.nan;
  if (!result.isFinite) {
    throw const UsageParseException();
  }
  return result;
}

double? _optionalFinite(Object? value) {
  if (value == null) {
    return null;
  }
  return _finite(value);
}

int? _optionalInteger(Object? value) {
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return null;
}

String? _text(Object? value) {
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

DateTime? _dateValue(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
  }
  if (value is num && value.isFinite) {
    return DateTime.fromMillisecondsSinceEpoch(
      (value.toDouble() * 1000).round(),
      isUtc: true,
    ).toLocal();
  }
  return null;
}

String _slug(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

String _titleCase(String value) {
  final normalized = value.replaceAll('_', ' ').trim();
  return normalized
      .split(RegExp(r'\s+'))
      .map(
        (part) => part.isEmpty
            ? part
            : '${part.substring(0, 1).toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}
