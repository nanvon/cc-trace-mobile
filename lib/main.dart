import 'package:flutter/material.dart';

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
          home: UsageScreen(controller: widget.controller),
        );
      },
    );
  }
}
