import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_controller.dart';
import 'auth/oauth_coordinator.dart';
import 'domain/app_settings.dart';
import 'providers/provider_api.dart';
import 'storage/credentials_store.dart';
import 'storage/local_store.dart';
import 'ui/app_theme.dart';
import 'ui/usage_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 透明状态栏只有在 edge-to-edge 下才生效；Android 15 起系统已强制该模式。
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final credentials = SecureCredentialsStore();
  final controller = AppController(
    credentials: credentials,
    localStore: SharedPreferencesLocalStore(),
    oauth: OAuthCoordinator(),
    providerApi: ProviderApi(credentials: credentials),
  );
  runApp(MainApp(controller: controller));
}

class MainApp extends StatefulWidget {
  const MainApp({required this.controller, super.key});

  final AppController controller;

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.bootstrap();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'CC Trace',
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: switch (widget.controller.settings.appearance) {
            AppearancePreference.system => ThemeMode.system,
            AppearancePreference.light => ThemeMode.light,
            AppearancePreference.dark => ThemeMode.dark,
          },
          // 无 AppBar 页面的全局默认；有 AppBar 的页面由 appBarTheme 覆盖。
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: systemOverlayStyleFor(Theme.of(context).brightness),
            child: child ?? const SizedBox.shrink(),
          ),
          home: UsageScreen(controller: widget.controller),
        );
      },
    );
  }
}
