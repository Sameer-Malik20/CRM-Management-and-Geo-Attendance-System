import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/services/authentication.dart';
import 'package:geo_attendance_system/src/ui/pages/splash_screen.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F3EC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: dashBoardColor,
          primary: dashBoardColor,
          secondary: leaveCardcolor,
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        fontFamily: "Poppins-Medium",
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontFamily: "Bitter",
            fontWeight: FontWeight.w700,
            color: appbarcolor,
          ),
          displayMedium: TextStyle(
            fontFamily: "Bitter",
            fontWeight: FontWeight.w700,
            color: appbarcolor,
          ),
          headlineLarge: TextStyle(
            fontFamily: "Bitter",
            fontWeight: FontWeight.w700,
            color: appbarcolor,
          ),
          headlineMedium: TextStyle(
            fontFamily: "Bitter",
            fontWeight: FontWeight.w700,
            color: appbarcolor,
          ),
          titleLarge: TextStyle(
            fontFamily: "Poppins-Bold",
            fontWeight: FontWeight.w700,
            color: appbarcolor,
          ),
          bodyLarge: TextStyle(
            fontFamily: "Poppins-Medium",
            color: Color(0xFF32404D),
          ),
          bodyMedium: TextStyle(
            fontFamily: "Poppins-Medium",
            color: Color(0xFF53606D),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: "Bitter",
            fontWeight: FontWeight.w700,
            fontSize: 24,
            color: Colors.white,
            letterSpacing: 0.4,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.92),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: dashBoardColor.withValues(alpha: 0.10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: leaveCardcolor, width: 1.4),
          ),
          hintStyle: const TextStyle(
            color: Color(0xFF7A8691),
            fontFamily: "Poppins-Medium",
          ),
          labelStyle: const TextStyle(
            color: dashBoardColor,
            fontFamily: "Poppins-Medium",
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: dashBoardColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontFamily: "Poppins-Bold",
              fontSize: 15,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
      home: Scaffold(
        body: SplashScreenWidget(
          auth: new Auth(),
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
