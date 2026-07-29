import 'dart:convert';

import '../domain/quota_models.dart';

class ParsedUsage {
  const ParsedUsage({required this.snapshot, this.identity});

  final QuotaSnapshot snapshot;
  final ProviderIdentity? identity;
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
    isActive: true,
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
      final active = row['is_active'] as bool? ?? true;
      final reset = _dateValue(row['resets_at']);
      switch (kind) {
        case 'session':
          session = _window(
            id: 'claude.five-hour',
            kind: QuotaWindowKind.fiveHour,
            used: used,
            reset: reset,
            seconds: 18000,
            active: active,
          );
        case 'weekly_all':
          weekly = _window(
            id: 'claude.weekly',
            kind: QuotaWindowKind.weekly,
            used: used,
            reset: reset,
            seconds: 604800,
            active: active,
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
            active: active,
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
              active: active,
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
  final plan =
      _text(root['subscriptionType']) ??
      _text(root['subscription_type']) ??
      _text(root['rate_limit_tier']);
  return ParsedUsage(
    snapshot: QuotaSnapshot(windows: windows, capturedAt: capturedAt),
    identity: plan == null ? null : ProviderIdentity(plan: _titleCase(plan)),
  );
}

ResetCreditsSnapshot parseResetCredits(String input) {
  final root = _object(jsonDecode(input));
  final available =
      _optionalInteger(root['available_count']) ??
      _optionalInteger(root['availableCount']) ??
      0;
  final credits = root['credits'];
  DateTime? earliest;
  if (credits is List<Object?>) {
    for (final value in credits.whereType<Map>()) {
      final row = value.cast<String, Object?>();
      final status = _text(row['status']);
      if (status != null && status != 'available') {
        continue;
      }
      final expiry = _dateValue(row['expires_at'] ?? row['expiresAt']);
      if (expiry != null && (earliest == null || expiry.isBefore(earliest))) {
        earliest = expiry;
      }
    }
  }
  return ResetCreditsSnapshot(
    availableCount: available,
    earliestExpiry: earliest,
  );
}

QuotaWindow _window({
  required String id,
  required QuotaWindowKind kind,
  required double used,
  required DateTime? reset,
  required bool active,
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
    isActive: active,
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
    active: true,
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
