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
    test(
      'ignores is_active while merging dynamic, legacy and model windows',
      () {
        final parsed = parseClaudeUsage('''
        {
          "subscriptionType": "max_5x",
          "limits": [
            {
              "kind": "session",
              "percent": 1,
              "is_active": false,
              "resets_at": "2026-07-29T13:00:00Z"
            },
            {
              "kind": "weekly_all",
              "percent": 45,
              "is_active": false
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
        expect(parsed.snapshot.primary.remainingPercent, 99);
        expect(parsed.snapshot.primary.resetsAt, isNotNull);
        final weekly = parsed.snapshot.windows.firstWhere(
          (window) => window.kind == QuotaWindowKind.weekly,
        );
        expect(weekly.resetsAt, isNotNull);
        final fable = parsed.snapshot.windows.firstWhere(
          (window) => window.displayName == 'Fable',
        );
        expect(fable.remainingPercent, 0);
        expect(fable.resetsAt, isNull);
        expect(parsed.identity?.plan, 'Max 5x');
      },
    );

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

  test('codex usage exposes the credits balance alongside the quota', () {
    final parsed = parseCodexUsage('''
      {
        "plan_type": "plus",
        "rate_limit": {
          "primary_window": {
            "used_percent": 100,
            "limit_window_seconds": 18000,
            "reset_at": 1788099726
          },
          "secondary_window": {
            "used_percent": 31,
            "limit_window_seconds": 604800,
            "reset_at": 1788643994
          }
        },
        "credits": {
          "has_credits": true,
          "unlimited": false,
          "overage_limit_reached": false,
          "balance": "4763.2323960000"
        }
      }
      ''', DateTime(2026, 8, 30));

    expect(parsed.credits?.hasCredits, isTrue);
    expect(parsed.credits?.unlimited, isFalse);
    expect(parsed.credits?.overageLimitReached, isFalse);
    // 十进制字符串原样保留：取整是展示决定，不在解析期做。
    expect(parsed.credits?.balance, '4763.2323960000');
    expect(parsed.snapshot.primary.remainingPercent, 0);
  });

  test('codex usage without credits still parses the quota', () {
    final parsed = parseCodexUsage('''
      {
        "rate_limit": {
          "primary_window": {"used_percent": 10, "limit_window_seconds": 18000}
        },
        "credits": null
      }
      ''', DateTime(2026, 8, 30));

    expect(parsed.credits, isNull);
    expect(parsed.snapshot.primary.remainingPercent, 90);
  });

  test('claude usage exposes spend amounts in minor units', () {
    final parsed = parseClaudeUsage('''
      {
        "limits": [
          {
            "kind": "session",
            "percent": 76,
            "resets_at": "2026-08-30T13:49:59Z"
          }
        ],
        "spend": {
          "used": {"amount_minor": 1739, "currency": "USD", "exponent": 2},
          "limit": {"amount_minor": 4000, "currency": "USD", "exponent": 2},
          "percent": 43,
          "enabled": true,
          "balance": null,
          "auto_reload": null
        }
      }
      ''', DateTime(2026, 8, 30));

    expect(parsed.spend?.enabled, isTrue);
    expect(parsed.spend?.hasAmounts, isTrue);
    expect(parsed.spend?.used?.amountMinor, 1739);
    expect(parsed.spend?.used?.currency, 'USD');
    expect(parsed.spend?.used?.exponent, 2);
    expect(parsed.spend?.limit?.amountMinor, 4000);
    expect(parsed.spend?.percent, 43);
  });

  test('a malformed spend never fails the whole usage parse', () {
    final parsed = parseClaudeUsage('''
      {
        "limits": [{"kind": "session", "percent": 20, "resets_at": null}],
        "spend": {"enabled": true, "percent": "43%", "used": {}}
      }
      ''', DateTime(2026, 8, 30));

    expect(parsed.snapshot.primary.remainingPercent, 80);
    expect(parsed.spend?.percent, isNull);
    expect(parsed.spend?.hasAmounts, isFalse);
  });
}
