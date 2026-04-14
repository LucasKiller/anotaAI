import 'package:flutter/material.dart';

import 'app.dart';
import 'core/auth/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authController = AuthController();
  await authController.bootstrap();
  runApp(AnotaAiApp(authController: authController));
}
