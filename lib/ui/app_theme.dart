import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.foreground,
    required this.content1,
    required this.content2,
    required this.default100,
    required this.default200,
    required this.default300,
    required this.default400,
    required this.default500,
    required this.default600,
    required this.divider,
    required this.primary,
    required this.primaryForeground,
    required this.success,
    required this.warning,
    required this.danger,
    required this.low,
  });

  static const light = AppPalette(
    background: Color(0xffffffff),
    foreground: Color(0xff11181c),
    content1: Color(0xffffffff),
    content2: Color(0xfff4f4f5),
    default100: Color(0xfff4f4f5),
    default200: Color(0xffe4e4e7),
    default300: Color(0xffd4d4d8),
    default400: Color(0xffa1a1aa),
    default500: Color(0xff71717a),
    default600: Color(0xff52525b),
    divider: Color(0x1c111111),
    primary: Color(0xff006fee),
    primaryForeground: Color(0xffffffff),
    success: Color(0xff17c964),
    warning: Color(0xfff5a524),
    danger: Color(0xfff31260),
    low: Color(0xfff3730e),
  );

  static const dark = AppPalette(
    background: Color(0xff000000),
    foreground: Color(0xffecedee),
    content1: Color(0xff18181b),
    content2: Color(0xff27272a),
    default100: Color(0xff27272a),
    default200: Color(0xff3f3f46),
    default300: Color(0xff52525b),
    default400: Color(0xff71717a),
    default500: Color(0xffa1a1aa),
    default600: Color(0xffd4d4d8),
    divider: Color(0x21ffffff),
    primary: Color(0xff338ef7),
    primaryForeground: Color(0xff001731),
    success: Color(0xff45d483),
    warning: Color(0xfff5a524),
    danger: Color(0xfff5455c),
    low: Color(0xffff8a3d),
  );

  final Color background;
  final Color foreground;
  final Color content1;
  final Color content2;
  final Color default100;
  final Color default200;
  final Color default300;
  final Color default400;
  final Color default500;
  final Color default600;
  final Color divider;
  final Color primary;
  final Color primaryForeground;
  final Color success;
  final Color warning;
  final Color danger;
  final Color low;

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    return t < .5 || other == null ? this : other;
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

/// 状态栏 / 导航栏保持透明，底色由页面自身背景提供，因此只需按主题明暗决定图标颜色。
/// Android 15 起系统强制 edge-to-edge 并忽略 statusBarColor，填色方案在新系统上无效。
SystemUiOverlayStyle systemOverlayStyleFor(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    // Android 看图标亮度，iOS 看背景亮度，两者语义相反。
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: isDark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}

ThemeData buildAppTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: palette.primary,
    onPrimary: palette.primaryForeground,
    secondary: palette.primary,
    onSecondary: palette.primaryForeground,
    error: palette.danger,
    onError: palette.background,
    surface: palette.content1,
    onSurface: palette.foreground,
    surfaceContainerHighest: palette.content2,
    outline: palette.default400,
    outlineVariant: palette.divider,
  );
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? palette.background
        : palette.content2,
    extensions: [palette],
    useMaterial3: true,
    splashFactory: InkSparkle.splashFactory,
    fontFamily: '.SF Pro Text',
    fontFamilyFallback: const ['PingFang SC', 'Noto Sans SC', 'sans-serif'],
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
      bodyColor: palette.foreground,
      displayColor: palette.foreground,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: palette.foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      // AppBar 自带 AnnotatedRegion，会盖掉 MaterialApp.builder 里的全局默认，
      // 且透明背景推不出正确的图标亮度，必须显式指定。
      systemOverlayStyle: systemOverlayStyleFor(brightness),
    ),
    dividerColor: palette.divider,
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.primary,
      linearTrackColor: palette.default100,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.primary,
        foregroundColor: palette.primaryForeground,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.foreground,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: BorderSide(color: palette.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
