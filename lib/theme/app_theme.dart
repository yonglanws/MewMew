import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 应用主题配置
class AppTheme {
  static const seed = Color(0xFF6B66C2); // 参考截图的柔和紫蓝色
  static const secondary = Color(0xFF3DD598);

  // 统一设计令牌
  static const radiusSm = 12.0;
  static const radiusMd = 16.0;
  static const radiusLg = 20.0;
  static const radiusXl = 28.0;
  static const spaceXs = 6.0;
  static const spaceSm = 10.0;
  static const spaceMd = 14.0;
  static const spaceLg = 20.0;
  static const durationFast = Duration(milliseconds: 150);
  static const durationMid = Duration(milliseconds: 220);
  static const durationSlow = Duration(milliseconds: 320);

  // 缓存主题数据，避免深浅色切换时重复计算 ColorScheme.fromSeed
  static ThemeData? _lightTheme;
  static ThemeData? _darkTheme;

  /// 获取浅色主题（带缓存）
  static ThemeData lightTheme() =>
      _lightTheme ??= theme(Brightness.light);

  /// 获取深色主题（带缓存）
  static ThemeData darkTheme() =>
      _darkTheme ??= theme(Brightness.dark);

  static ThemeData theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF7F7FB)
          : const Color(0xFF12121A),
      appBarTheme: AppBarTheme(
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        backgroundColor: brightness == Brightness.light
            ? const Color(0xFFF7F7FB)
            : const Color(0xFF12121A),
        foregroundColor: brightness == Brightness.light
            ? const Color(0xFF1B1B21)
            : const Color(0xFFE6E6EE),
        systemOverlayStyle: brightness == Brightness.light
            ? SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: const Color(0xFFF7F7FB),
                systemNavigationBarIconBrightness: Brightness.dark,
              )
            : SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: const Color(0xFF12121A),
                systemNavigationBarIconBrightness: Brightness.light,
              ),
        titleTextStyle: TextStyle(
          color: brightness == Brightness.light
              ? const Color(0xFF1B1B21)
              : const Color(0xFFE6E6EE),
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        color: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF1C1C26),
      ),
      dividerTheme: const DividerThemeData(
        space: 1,
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light
            ? const Color(0xFFEFEFF6)
            : const Color(0xFF23232F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        side: BorderSide.none,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: brightness == Brightness.light
            ? const Color(0xFFF2F2F8)
            : const Color(0xFF181820),
        width: 304,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(radiusXl),
            bottomRight: Radius.circular(radiusXl),
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: brightness == Brightness.light
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF1C1C26),
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: brightness == Brightness.light
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF1C1C26),
        modalBarrierColor: Colors.black54,
        elevation: 12,
        modalElevation: 12,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          // 使用原生 ZoomPageTransitionsBuilder，支持手势打断
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}
