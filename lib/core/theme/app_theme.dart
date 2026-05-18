import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  static const Color primaryGreen = Color(0xFF1B5E20);
  static const Color accentGold = Color(0xFFFFB300);
  static const Color surfaceDark = Color(0xFF121212);
  static const Color cardDark = Color(0xFF1E1E1E);
  static const Color winColor = Color(0xFFFFD700);
  static const Color placeColor = Color(0xFFC0C0C0);
  static const Color showColor = Color(0xFFCD7F32);
  static const Color positiveGreen = Color(0xFF4CAF50);
  static const Color negativeRed = Color(0xFFE53935);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: primaryGreen,
        secondary: accentGold,
        surface: surfaceDark,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: Colors.white,
        // Material 3 ChoiceChip / FilterChip 가 '선택' 상태일 때
        // 라벨 색으로 onSecondaryContainer 를 사용한다. 기본값이
        // 어두운 색이라 녹색 배경 위에서 검은 글씨로 보이므로 흰색으로
        // 강제한다. (특히 iOS Safari CanvasKit 에서 가독성이 떨어짐)
        secondaryContainer: primaryGreen,
        onSecondaryContainer: Colors.white,
      ),
      scaffoldBackgroundColor: surfaceDark,
      textTheme: GoogleFonts.notoSansKrTextTheme(
        ThemeData.dark().textTheme,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.notoSansKr(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardDark,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accentGold,
        unselectedLabelColor: Colors.grey,
        indicatorColor: accentGold,
        labelStyle: GoogleFonts.notoSansKr(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cardDark,
        selectedItemColor: accentGold,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardDark,
        selectedColor: primaryGreen,
        // 모든 WidgetState(특히 selected) 에서 라벨 색을 흰색으로 고정한다.
        // 단순한 TextStyle 의 color 는 Material 3 ChoiceChip 의 내부
        // WidgetStateColor 분기에 의해 덮어써질 수 있어 WidgetStateTextStyle
        // 로 명시한다.
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) => GoogleFonts.notoSansKr(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: Colors.white,
          ),
        ),
        secondaryLabelStyle: GoogleFonts.notoSansKr(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: primaryGreen,
        secondary: accentGold,
        surface: Colors.grey.shade50,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
      ),
      textTheme: GoogleFonts.notoSansKrTextTheme(
        ThemeData.light().textTheme,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.notoSansKr(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryGreen,
        unselectedLabelColor: Colors.grey,
        indicatorColor: primaryGreen,
        labelStyle: GoogleFonts.notoSansKr(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryGreen,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
