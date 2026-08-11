import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Primary brand palette — deep blue to vibrant indigo
  static const primary = Color(0xFF4338CA);      // Indigo-700
  static const primaryLight = Color(0xFF6366F1);  // Indigo-500
  static const primaryDark = Color(0xFF312E81);   // Indigo-900

  // Accent — neon gold/amber for election feel
  static const accent = Color(0xFFF59E0B);        // Amber-500
  static const accentLight = Color(0xFFFCD34D);   // Amber-300

  // Surface / Background (Global gradient base)
  static const background = Color(0xFF0F172A);    // Slate-900
  static const surface = Color(0xFF1E293B);       // Slate-800
  static const surfaceVariant = Color(0xFF334155); // Slate-700
  static const cardColor = Color(0x801E293B);     // Semi-transparent for glassmorphism

  // Text
  static const textPrimary = Color(0xFFF8FAFC);   // Slate-50
  static const textSecondary = Color(0xFF94A3B8);  // Slate-400
  static const textMuted = Color(0xFF64748B);      // Slate-500

  // Status (Vibrant versions)
  static const success = Color(0xFF10B981);  // Emerald-500
  static const warning = Color(0xFFF59E0B);  // Amber-500
  static const error = Color(0xFFEF4444);    // Red-500
  static const info = Color(0xFF0EA5E9);     // Sky-500

  // State badges
  static const stateDraft = Color(0xFF64748B);
  static const statePublished = Color(0xFF3B82F6);
  static const stateNominations = Color(0xFF8B5CF6);
  static const stateVoting = Color(0xFF10B981);
  static const stateClosed = Color(0xFFF59E0B);
  static const stateResults = Color(0xFFF97316);

  // Light Theme specific colors
  static const backgroundLight = Color(0xFFF1F5F9); // Slate-100 for better contrast
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceVariantLight = Color(0xFFF8FAFC); // Slate-50
  static const cardColorLight = Color(0xB3FFFFFF); // 70% white for frosted glass
  
  static const textPrimaryLightMode = Color(0xFF0F172A); // Slate-900
  static const textSecondaryLightMode = Color(0xFF475569); // Slate-600
  static const textMutedLightMode = Color(0xFF94A3B8); // Slate-400

  // Gradients
  static const LinearGradient globalBackgroundGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      Color(0xFF0F172A), // Slate-900
      Color(0xFF0B1021), // Deeper dark
      Color(0xFF1E1B4B), // Indigo-950
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient globalBackgroundGradientLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF8FAFC), // Slate-50
      Color(0xFFEEF2FF), // Indigo-50
      Color(0xFFE0E7FF), // Indigo-100
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryLight, primary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient warningGradient = LinearGradient(
    colors: [Color(0xFFFBBF24), Color(0xFFD97706)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static ThemeData get dark {
    final baseTextTheme = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);
    final headingFont = GoogleFonts.outfit;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: AppColors.primaryLight,
        primaryContainer: AppColors.primaryDark,
        secondary: AppColors.accent,
        surface: const Color(0xFF09090B), // Deep sleek black
        error: AppColors.error,
        onPrimary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      scaffoldBackgroundColor: const Color(0xFF09090B),
      cardTheme: CardThemeData(
        color: const Color(0xFF18181B), // Slightly lighter black for cards
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF27272A), width: 1), // Crisp border
        ),
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: headingFont(
          fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white,
        ),
        headlineMedium: headingFont(
          fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white,
        ),
        titleLarge: headingFont(
          fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white,
        ),
        titleMedium: headingFont(
          fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w400, color: const Color(0xFFFAFAFA),
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w400, color: const Color(0xFFA1A1AA),
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF09090B),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: headingFont(
          fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), // Less rounded, more professional
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.surfaceVariant),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.surfaceVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.surfaceVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceVariant,
        labelStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.transparent),
        ),
      ),
      dividerColor: AppColors.surfaceVariant,
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primaryLight,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  static ThemeData get light {
    final baseTextTheme = GoogleFonts.interTextTheme(ThemeData.light().textTheme);
    final headingFont = GoogleFonts.outfit;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        primaryContainer: AppColors.primaryLight,
        secondary: AppColors.accent,
        surface: const Color(0xFFFFFFFF),
        error: AppColors.error,
        onPrimary: Colors.white,
        onSurface: AppColors.textPrimaryLightMode,
      ),
      scaffoldBackgroundColor: const Color(0xFFFAFAFA), // Clean crisp white-grey
      cardTheme: CardThemeData(
        color: const Color(0xFFFFFFFF), // Pure white cards
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE4E4E7), width: 1), // Crisp light border
        ),
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: headingFont(
          fontSize: 32, fontWeight: FontWeight.bold, color: const Color(0xFF171717), // Near black
        ),
        headlineMedium: headingFont(
          fontSize: 22, fontWeight: FontWeight.w700, color: const Color(0xFF171717),
        ),
        titleLarge: headingFont(
          fontSize: 18, fontWeight: FontWeight.w600, color: const Color(0xFF171717),
        ),
        titleMedium: headingFont(
          fontSize: 16, fontWeight: FontWeight.w500, color: const Color(0xFF171717),
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w400, color: const Color(0xFF171717),
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w400, color: const Color(0xFF52525B), // Muted grey
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF171717),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFFFFFFFF),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: headingFont(
          fontSize: 18, fontWeight: FontWeight.w600, color: const Color(0xFF171717),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF171717)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF171717),
          side: const BorderSide(color: Color(0xFFE4E4E7)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: GoogleFonts.inter(color: const Color(0xFFA1A1AA), fontSize: 14),
        labelStyle: GoogleFonts.inter(color: const Color(0xFF52525B), fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFFFFFFF),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceVariantLight,
        labelStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryLightMode),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.transparent),
        ),
      ),
      dividerColor: AppColors.surfaceVariantLight,
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceLight,
        selectedItemColor: AppColors.primaryLight,
        unselectedItemColor: AppColors.textMutedLightMode,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
