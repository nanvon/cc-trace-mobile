import 'dart:async';

import 'package:cc_trace_mobile/diagnostics/app_diagnostics.dart';
import 'package:cc_trace_mobile/storage/diagnostics_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 带敏感信息的异常：诊断日志绝不能把它的消息写出去。
class _LeakyException implements Exception {
  const _LeakyException();

  @override
  String toString() =>
      'Failed with access_token=sk-ant-secret-value for user@example.com';
}

/// 读盘慢到可以手动放行，用来检查「历史还没回来就写盘」的竞态。
class _GatedDiagnosticsStore implements DiagnosticsStore {
  _GatedDiagnosticsStore(this.saved);

  List<String> saved;
  final Completer<void> gate = Completer<void>();
  int writes = 0;

  @override
  Future<List<String>> read() async {
    await gate.future;
    return saved;
  }

  @override
  Future<void> write(List<String> entries) async {
    writes++;
    saved = List.of(entries);
  }

  @override
  Future<void> clear() async {
    saved = [];
  }
}

void main() {
  test('keeps only the most recent entries', () {
    final diagnostics = AppDiagnostics(capacity: 5, now: () => DateTime(2026));
    for (var i = 0; i < 20; i++) {
      diagnostics.record('event', {'i': i});
    }
    final entries = diagnostics.entries;
    expect(entries, hasLength(5));
    expect(entries.last, contains('i=19'));
    expect(entries.first, contains('i=15'));
    diagnostics.dispose();
  });

  test('stamps the date once per day, not on every entry', () {
    var now = DateTime(2026, 9, 13, 23, 59);
    final diagnostics = AppDiagnostics(now: () => now);
    diagnostics.record('a');
    diagnostics.record('b');
    now = DateTime(2026, 9, 14, 0, 1);
    diagnostics.record('c');

    final dateLines = diagnostics.entries
        .where((entry) => entry.startsWith('——'))
        .toList();
    expect(dateLines, ['—— 2026-09-13 ——', '—— 2026-09-14 ——']);
    diagnostics.dispose();
  });

  test('records the error type and location, never the message', () async {
    final diagnostics = AppDiagnostics(now: () => DateTime(2026));
    diagnostics.recordError(
      'error.async',
      const _LeakyException(),
      StackTrace.current,
    );

    final exported = diagnostics.export();
    expect(exported, contains('error.async'));
    expect(exported, contains('type=_LeakyException'));
    expect(exported, isNot(contains('sk-ant-secret-value')));
    expect(exported, isNot(contains('user@example.com')));
    diagnostics.dispose();
  });

  test('clips an oversized entry instead of letting it crowd out history', () {
    final diagnostics = AppDiagnostics(now: () => DateTime(2026));
    diagnostics.record('event', {'blob': 'x' * 5000});
    expect(diagnostics.entries.last.length, lessThan(300));
    diagnostics.dispose();
  });

  test('separates runs with a blank line', () {
    final diagnostics = AppDiagnostics(now: () => DateTime(2026));
    diagnostics.record('first');
    diagnostics.newSection('app.start');
    expect(diagnostics.entries, contains(''));
    diagnostics.dispose();
  });

  test('restores saved entries ahead of the ones from this run', () async {
    final store = MemoryDiagnosticsStore()
      ..entries = ['—— 2026-09-12 ——', '10:00:00  previous.run'];
    final diagnostics = AppDiagnostics(now: () => DateTime(2026, 9, 13));
    diagnostics.record('app.start');
    await diagnostics.attach(store);

    expect(diagnostics.entries.first, '—— 2026-09-12 ——');
    expect(diagnostics.entries[1], contains('previous.run'));
    expect(diagnostics.entries.last, contains('app.start'));
    diagnostics.dispose();
  });

  test('round-trips through the store', () async {
    final store = MemoryDiagnosticsStore();
    final first = AppDiagnostics(now: () => DateTime(2026, 9, 13, 10));
    await first.attach(store);
    first.record('refresh.failed', {'kind': 'offline'});
    await first.flush();
    first.dispose();

    final second = AppDiagnostics(now: () => DateTime(2026, 9, 13, 11));
    await second.attach(store);
    expect(second.export(), contains('refresh.failed  kind=offline'));
    second.dispose();
  });

  test('clear wipes the persisted copy too', () async {
    final store = MemoryDiagnosticsStore();
    final diagnostics = AppDiagnostics(now: () => DateTime(2026));
    await diagnostics.attach(store);
    diagnostics.record('event');
    await diagnostics.flush();
    expect(store.entries, isNotEmpty);

    diagnostics.clear();
    await Future<void>.delayed(Duration.zero);
    expect(diagnostics.isEmpty, isTrue);
    expect(store.entries, isEmpty);
    diagnostics.dispose();
  });

  test('drops null fields instead of writing "null"', () {
    final diagnostics = AppDiagnostics(now: () => DateTime(2026));
    diagnostics.record('refresh.failed', {
      'kind': 'offline',
      'retryInSec': null,
    });
    expect(diagnostics.entries.last, endsWith('refresh.failed  kind=offline'));
    diagnostics.dispose();
  });

  test('folds a repeated event instead of filling the buffer with it', () {
    final diagnostics = AppDiagnostics(capacity: 10, now: () => DateTime(2026));
    diagnostics.record('app.start');
    for (var i = 0; i < 50; i++) {
      diagnostics.record('error.widget', {'type': 'StateError'});
    }

    // 日期行 + app.start + 一条折叠后的记录。
    expect(diagnostics.entries, hasLength(3));
    expect(
      diagnostics.entries.last,
      contains('error.widget  type=StateError  ×50 至 '),
    );
    diagnostics.dispose();
  });

  test('folds interleaved repeats, not just adjacent ones', () {
    // 一次刷新失败会连着记好几条不同的事件，只比对紧邻的上一条一条都折不掉。
    final diagnostics = AppDiagnostics(now: () => DateTime(2026));
    for (var i = 0; i < 100; i++) {
      diagnostics.record('http.unreachable', {'endpoint': 'usage'});
      diagnostics.record('refresh.failed', {'kind': 'offline'});
    }

    final events = diagnostics.entries.where((e) => e.contains(':')).toList();
    expect(events, hasLength(2));
    expect(events[0], contains('http.unreachable  endpoint=usage  ×100'));
    expect(events[1], contains('refresh.failed  kind=offline  ×100'));
    diagnostics.dispose();
  });

  test('an event that scrolled out of the fold window starts a new line', () {
    final diagnostics = AppDiagnostics(now: () => DateTime(2026));
    for (var i = 0; i < 9; i++) {
      diagnostics.record('event$i');
    }
    diagnostics.record('event0');

    expect(diagnostics.entries.last, endsWith('event0'));
    expect(diagnostics.entries.last, isNot(contains('×')));
    diagnostics.dispose();
  });

  test('a repeat on the next day is counted separately', () {
    var now = DateTime(2026, 9, 13, 23, 59);
    final diagnostics = AppDiagnostics(now: () => now);
    diagnostics.record('refresh.failed', {'kind': 'offline'});
    diagnostics.record('refresh.failed', {'kind': 'offline'});
    now = DateTime(2026, 9, 14, 0, 5);
    diagnostics.record('refresh.failed', {'kind': 'offline'});

    // 一条 ×N 横跨两天就看不出问题是哪天开始的，日期行必须能插进去。
    expect(diagnostics.entries, hasLength(4));
    expect(diagnostics.entries[1], contains('×2'));
    expect(diagnostics.entries[2], '—— 2026-09-14 ——');
    expect(diagnostics.entries[3], isNot(contains('×')));
    diagnostics.dispose();
  });

  test('a new section never folds into what came before it', () {
    final diagnostics = AppDiagnostics(now: () => DateTime(2026));
    diagnostics.record('app.start');
    diagnostics.newSection('app.start');
    expect(diagnostics.entries.last, isNot(contains('×')));
    diagnostics.dispose();
  });

  test('a repeated error is not written to disk over and over', () async {
    final store = _GatedDiagnosticsStore([])..gate.complete();
    // 防抖设得足够长，这样落盘次数只反映异常路径的立即写。
    final diagnostics = AppDiagnostics(
      now: () => DateTime(2026),
      flushDelay: const Duration(minutes: 5),
    );
    await diagnostics.attach(store);
    for (var i = 0; i < 20; i++) {
      diagnostics.recordError('error.widget', StateError('x'), null);
    }
    await Future<void>.delayed(Duration.zero);

    expect(store.writes, 1);
    diagnostics.dispose();
  });

  test('a flush before the history is back does not wipe it', () async {
    final store = _GatedDiagnosticsStore([
      '—— 2026-09-12 ——',
      '10:00:00  previous.run',
    ]);
    final diagnostics = AppDiagnostics(now: () => DateTime(2026, 9, 13));
    final attached = diagnostics.attach(store);
    diagnostics.record('app.start');
    final flushed = diagnostics.flush();

    // 写盘请求先到，读盘还堵着：放行后历史必须完好。
    store.gate.complete();
    await attached;
    await flushed;

    expect(store.saved, contains('10:00:00  previous.run'));
    expect(store.saved.last, contains('app.start'));
    diagnostics.dispose();
  });

  test('caps the whole log by size, not just by entry count', () {
    final diagnostics = AppDiagnostics(
      capacity: 100000,
      now: () => DateTime(2026),
    );
    for (var i = 0; i < 2000; i++) {
      diagnostics.record('event$i', {'blob': 'x' * 200});
    }
    final total = diagnostics.export().length;
    expect(total, lessThanOrEqualTo(64 * 1024));
    // 裁剪从头部开始，最新的记录必须留下。
    expect(diagnostics.entries.last, contains('event1999'));
    diagnostics.dispose();
  });

  test('flattens newlines so a round trip cannot split one entry', () async {
    final store = MemoryDiagnosticsStore();
    final diagnostics = AppDiagnostics(now: () => DateTime(2026));
    await diagnostics.attach(store);
    diagnostics.record('app.start', {'os': 'Linux 6.1\n#1 SMP'});
    await diagnostics.flush();

    expect(diagnostics.entries.last, contains('os=Linux 6.1 #1 SMP'));
    final restored = AppDiagnostics(now: () => DateTime(2026));
    await restored.attach(store);
    expect(restored.entries.length, diagnostics.entries.length);
    diagnostics.dispose();
    restored.dispose();
  });
}
