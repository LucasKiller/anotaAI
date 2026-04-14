import 'package:flutter/material.dart';

import 'core/auth/auth_controller.dart';
import 'features/auth/auth_page.dart';
import 'features/dashboard/dashboard_page.dart';

class AnotaAiApp extends StatelessWidget {
  const AnotaAiApp({super.key, required this.authController});

  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AnotaAi',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E6F5C)),
        scaffoldBackgroundColor: const Color(0xFFF5EFE3),
      ),
      home: AnimatedBuilder(
        animation: authController,
        builder: (context, _) {
          if (authController.isBootstrapping) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          if (!authController.isAuthenticated) {
            return AuthPage(authController: authController);
          }

          return DashboardPage(authController: authController);
        },
      ),
    );
  }
}
