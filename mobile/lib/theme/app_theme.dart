import 'package:flutter/material.dart';

/// iNAS iOS 风格统一主题
class AppTheme {
  // ============ 颜色 ============
  static const Color bg = Color(0xFF1C1C1E);
  static const Color card = Color(0xFF2C2C2E);
  static const Color cardAlt = Color(0xFF242426);
  static const Color accent = Color(0xFF007AFF);
  static const Color accentLight = Color(0xFF5AC8FA);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textTertiary = Color(0xFF636366);
  static const Color divider = Color(0xFF38383A);
  static const Color danger = Color(0xFFFF3B30);
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color terminalBg = Color(0xFF000000);
  static const Color terminalText = Color(0xFF4EC9B0);

  // ============ 圆角 ============
  static const double radiusCard = 14;
  static const double radiusButton = 10;
  static const double radiusIcon = 12;
  static const double radiusDialog = 14;
  static const double radiusSmall = 8;

  // ============ 间距 ============
  static const double paddingPage = 16;
  static const double paddingItem = 12;
  static const double gapGroup = 20;
  static const double gapItem = 8;

  // ============ 字体 ============
  static const double fontSizeTitle = 17;
  static const double fontSizeBody = 15;
  static const double fontSizeSecondary = 13;
  static const double fontSizeSmall = 11;

  // ============ 阴影 ============
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
  ];

  // ============ 文字样式 ============
  static const TextStyle titleStyle = TextStyle(
    color: textPrimary, fontSize: fontSizeTitle, fontWeight: FontWeight.w600,
  );
  static const TextStyle bodyStyle = TextStyle(
    color: textPrimary, fontSize: fontSizeBody, fontWeight: FontWeight.normal,
  );
  static const TextStyle secondaryStyle = TextStyle(
    color: textSecondary, fontSize: fontSizeSecondary, fontWeight: FontWeight.normal,
  );
  static const TextStyle smallStyle = TextStyle(
    color: textSecondary, fontSize: fontSizeSmall, fontWeight: FontWeight.normal,
  );

  // ============ 主题数据 ============
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: accent,
      scaffoldBackgroundColor: bg,
      cardColor: card,
      dividerColor: divider,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentLight,
        surface: card,
        error: danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(color: textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF1C1C1E),
        selectedItemColor: accent,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 8,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: textPrimary, fontSize: 28, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: textPrimary, fontSize: fontSizeTitle, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: textPrimary, fontSize: fontSizeBody),
        bodyMedium: TextStyle(color: textPrimary, fontSize: 14),
        labelSmall: TextStyle(color: textSecondary, fontSize: fontSizeSmall),
      ),
      iconTheme: const IconThemeData(color: textPrimary),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: card,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusDialog)),
        titleTextStyle: const TextStyle(color: textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: accent,
        textColor: textPrimary,
        tileColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? accent : Colors.grey),
        trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? accent.withOpacity(0.4) : Colors.grey.withOpacity(0.3)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: divider,
        thumbColor: accent,
        overlayColor: accent.withOpacity(0.2),
        trackHeight: 4,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: divider,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardAlt,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: divider), borderRadius: BorderRadius.circular(radiusButton)),
        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: accent), borderRadius: BorderRadius.circular(radiusButton)),
        hintStyle: const TextStyle(color: textTertiary),
      ),
    );
  }
}
