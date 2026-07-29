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

  testWidgets('renders low quota, model rows and inactive neutral copy', (
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

    expect(find.text('15%'), findsOneWidget);
    expect(find.text('Opus 每周'), findsOneWidget);
    expect(find.text('Fable 每周'), findsOneWidget);
    expect(find.text('当前不可用'), findsOneWidget);
    expect(find.text('3 次可用'), findsOneWidget);
    expect(find.text('Plus'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
    expect(find.text('na•••@example.com'), findsNWidgets(2));
    expect(find.text('2 天后重置'), findsOneWidget);
    expect(find.text('4 小时后重置'), findsOneWidget);
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
    expect(find.text('重置次数'), findsNothing);
    controller.dispose();
  });

  testWidgets('does not render an inactive primary window as usable quota', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 29, 9);
    final credentials = MemoryCredentialsStore();
    await credentials.write(fakeToken(ProviderId.claude, now: now));
    final controller = _controller(
      credentials: credentials,
      now: now,
      gateway: FakeProviderGateway(
        (provider) async => fakeSuccess(
          provider,
          now: now,
          remaining: 78,
          primaryActive: false,
        ),
      ),
    );

    await controller.bootstrap();
    await _pump(tester, controller);

    expect(find.text('78%'), findsNothing);
    expect(find.text('当前不可用'), findsOneWidget);
    expect(find.text('--'), findsNWidgets(2));
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
