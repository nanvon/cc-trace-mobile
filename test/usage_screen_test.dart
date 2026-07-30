import 'package:cc_trace_mobile/app/app_controller.dart';
import 'package:cc_trace_mobile/domain/quota_models.dart';
import 'package:cc_trace_mobile/storage/credentials_store.dart';
import 'package:cc_trace_mobile/storage/local_store.dart';
import 'package:cc_trace_mobile/ui/app_theme.dart';
import 'package:cc_trace_mobile/ui/usage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first load and onboarding are both reachable', (tester) async {
    final controller = _controller();
    await _pump(tester, controller);

    expect(find.text('正在检查额度'), findsNWidgets(2));

    await controller.bootstrap();
    await tester.pump();

    expect(find.text('先登录，\n才能看到额度'), findsOneWidget);
    expect(find.text('登录 Codex'), findsOneWidget);
    expect(find.text('登录 Claude Code'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('renders low quota and model rows from returned percentages', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(fakeToken(ProviderId.codex, now: now));
    await credentials.write(fakeToken(ProviderId.claude, now: now));
    final controller = _controller(
      credentials: credentials,
      now: now,
      gateway: FakeProviderGateway(
        (provider) async => fakeSuccess(
          provider,
          now: now,
          remaining: 15,
          includeModel: provider == ProviderId.claude,
        ),
      ),
    );
    await controller.bootstrap();
    await _pump(tester, controller);

    expect(find.text('15%', findRichText: true), findsOneWidget);
    expect(find.text('ALL'), findsOneWidget);
    expect(find.text('OPUS'), findsOneWidget);
    expect(find.text('FABLE'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('当前不可用'), findsNothing);
    expect(find.text('3 次'), findsOneWidget);
    expect(find.text('Plus'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
    expect(find.text('sample@example.com'), findsNWidgets(2));
    expect(find.text('2d'), findsOneWidget);
    expect(find.text('4h'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('one signed-out provider remains a card with a login action', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(fakeToken(ProviderId.claude, now: now));
    final controller = _controller(
      credentials: credentials,
      now: now,
      gateway: FakeProviderGateway(
        (provider) async => fakeSuccess(provider, now: now),
      ),
    );
    await controller.bootstrap();
    await _pump(tester, controller);

    expect(find.text('还没登录 Codex'), findsOneWidget);
    expect(find.text('登录后才能读到额度'), findsOneWidget);
    expect(find.text('RESETS'), findsNothing);
    controller.dispose();
  });

  testWidgets('Codex card expansion is reversible and shows credit expiries', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(fakeToken(ProviderId.codex, now: now));
    final controller = _controller(
      credentials: credentials,
      now: now,
      gateway: FakeProviderGateway(
        (provider) async => fakeSuccess(provider, now: now),
      ),
    );
    await controller.bootstrap();
    await _pump(tester, controller);

    final card = find.byKey(const ValueKey(ProviderId.codex));
    final collapsedHeight = tester.getSize(card).height;

    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(card).height, greaterThan(collapsedHeight));

    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(card).height,
      moreOrLessEquals(collapsedHeight, epsilon: .5),
    );

    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, greaterThan(collapsedHeight));
    // 展开态只补充折叠态没有的信息：每批次数各自的过期时刻。
    // 卡片上已经用倒计时给过的窗口重置时间不再重复列出。
    expect(find.text('8/4 09:00'), findsOneWidget);
    expect(find.text('8/5 09:00'), findsOneWidget);
    expect(find.text('8/6 09:00'), findsOneWidget);
    expect(find.text('7/31 09:00'), findsNothing);
    expect(find.text('1 次'), findsNWidgets(3));
    controller.dispose();
  });

  testWidgets('renders a Claude primary percentage and reset time', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(fakeToken(ProviderId.claude, now: now));
    final controller = _controller(
      credentials: credentials,
      now: now,
      gateway: FakeProviderGateway(
        (provider) async => fakeSuccess(provider, now: now),
      ),
    );

    await controller.bootstrap();
    await _pump(tester, controller);

    expect(find.text('78%', findRichText: true), findsOneWidget);
    expect(find.text('4h'), findsOneWidget);
    expect(find.text('未开始'), findsNothing);
    expect(find.text('当前不可用'), findsNothing);
    // 占位符只限定在 Claude 卡片内检查：同屏未登录的 Codex 卡片本来就该显示 `--`。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey(ProviderId.claude)),
        matching: find.text('--'),
      ),
      findsNothing,
    );
    controller.dispose();
  });

  testWidgets('renders normal and onboarding golden references', (
    tester,
  ) async {
    await _setPhoneSurface(tester);
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(fakeToken(ProviderId.codex, now: now));
    await credentials.write(fakeToken(ProviderId.claude, now: now));
    final normal = _controller(
      credentials: credentials,
      now: now,
      gateway: FakeProviderGateway(
        (provider) async => fakeSuccess(provider, now: now),
      ),
    );
    await normal.bootstrap();
    await _pump(tester, normal);
    await expectLater(
      find.byType(UsageScreen),
      matchesGoldenFile('goldens/usage-normal-light.png'),
    );
    normal.dispose();

    final onboarding = _controller();
    await onboarding.bootstrap();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: UsageScreen(controller: onboarding),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(UsageScreen),
      matchesGoldenFile('goldens/usage-onboarding-dark.png'),
    );
    onboarding.dispose();
    await _clearPhoneSurface(tester);
  });
}

AppController _controller({
  MemoryCredentialsStore? credentials,
  FakeProviderGateway? gateway,
  DateTime? now,
}) {
  final local = MemoryLocalStore()..installed = true;
  return AppController(
    credentials: credentials ?? MemoryCredentialsStore(),
    localStore: local,
    oauth: FakeOAuthGateway(),
    providerApi:
        gateway ??
        FakeProviderGateway(
          (provider) async => fakeSuccess(provider, now: now),
        ),
    now: () => now ?? DateTime(2026, 7, 29, 9),
  );
}

Future<void> _pump(WidgetTester tester, AppController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: UsageScreen(controller: controller),
    ),
  );
  await tester.pump();
}

Future<void> _setPhoneSurface(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 852);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}

Future<void> _clearPhoneSurface(WidgetTester tester) async {
  tester.view.resetDevicePixelRatio();
  tester.view.resetPhysicalSize();
}
