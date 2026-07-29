import 'package:cc_trace_mobile/domain/quota_models.dart';
import 'package:cc_trace_mobile/providers/usage_parsers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Codex usage parser', () {
    test('normalizes primary and secondary windows without assuming count', () {
      final capturedAt = DateTime(2026, 7, 29, 9);
      final parsed = parseCodexUsage('''
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 41,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 3600
            },
            "secondary_window": {
              "used_percent": 12.5,
              "limit_window_seconds": 18000,
              "reset_at": 1785300000
            }
          }
        }
        ''', capturedAt);

      expect(parsed.snapshot.windows, hasLength(2));
      expect(parsed.snapshot.primary.kind, QuotaWindowKind.weekly);
      expect(parsed.snapshot.primary.remainingPercent, 59);
      expect(parsed.snapshot.primary.isPrimary, isTrue);
      expect(parsed.snapshot.windows[1].kind, QuotaWindowKind.fiveHour);
      expect(parsed.snapshot.windows[1].remainingPercent, 87.5);
      expect(parsed.identity?.plan, 'Plus');
    });

    test('keeps an unrecognized or missing duration as unknown', () {
      final parsed = parseCodexUsage('''
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 130,
              "reset_after_seconds": 60
            }
          }
        }
        ''', DateTime(2026, 7, 29, 9));

      expect(parsed.snapshot.primary.kind, QuotaWindowKind.unknown);
      expect(parsed.snapshot.primary.windowSeconds, isNull);
      expect(parsed.snapshot.primary.remainingPercent, 0);
    });
  });

  group('Claude usage parser', () {
    test('merges dynamic, legacy, model and inactive windows', () {
      final parsed = parseClaudeUsage('''
        {
          "subscriptionType": "max_5x",
          "limits": [
            {
              "kind": "session",
              "percent": 22,
              "is_active": true,
              "resets_at": "2026-07-29T13:00:00Z"
            },
            {
              "kind": "weekly_all",
              "percent": 45,
              "is_active": true
            },
            {
              "kind": "weekly_scoped",
              "percent": 77,
              "is_active": true,
              "scope": {
                "model": {"id": "opus", "display_name": "Opus"}
              }
            },
            {
              "kind": "weekly_scoped",
              "percent": 100,
              "is_active": false,
              "scope": {"surface": "Fable"}
            }
          ],
          "seven_day": {
            "utilization": 46,
            "resets_at": "2026-08-01T00:00:00Z"
          }
        }
        ''', DateTime(2026, 7, 29, 9));

      expect(parsed.snapshot.windows, hasLength(4));
      expect(parsed.snapshot.primary.kind, QuotaWindowKind.fiveHour);
      final weekly = parsed.snapshot.windows.firstWhere(
        (window) => window.kind == QuotaWindowKind.weekly,
      );
      expect(weekly.resetsAt, isNotNull);
      final fable = parsed.snapshot.windows.firstWhere(
        (window) => window.displayName == 'Fable',
      );
      expect(fable.isActive, isFalse);
      expect(parsed.identity?.plan, 'Max 5x');
    });

    test('rejects a response without any supported usage window', () {
      expect(
        () => parseClaudeUsage('{}', DateTime(2026, 7, 29)),
        throwsA(isA<UsageParseException>()),
      );
    });
  });

  test('reset credits accepts snake and camel case fields', () {
    final credits = parseResetCredits('''
      {
        "availableCount": 3,
        "credits": [
          {"status": "used", "expiresAt": "2026-07-30T00:00:00Z"},
          {
            "id": "later",
            "status": "available",
            "resetType": "codex_rate_limits",
            "grantedAt": "2026-07-28T00:00:00Z",
            "expiresAt": "2026-08-04T00:00:00Z"
          },
          {
            "id": "earlier",
            "status": "available",
            "reset_type": "codex_rate_limits",
            "granted_at": "2026-07-27T00:00:00Z",
            "expires_at": "2026-08-02T00:00:00Z"
          }
        ]
      }
      ''');

    expect(credits.availableCount, 3);
    expect(credits.earliestExpiry?.day, 2);
    expect(credits.availableCredits, hasLength(2));
    expect(credits.availableCredits.first.id, 'earlier');
    expect(credits.availableCredits.first.resetType, 'codex_rate_limits');
    expect(credits.availableCredits.first.grantedAt?.day, 27);
    expect(credits.availableCredits.last.expiresAt?.day, 4);
  });
}
