import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

/// Root application widget for FoodSense.
///
/// This widget configures the global Flutter application settings:
/// - Application title
/// - Debug banner visibility
/// - Global theme
/// - Application navigation
class FoodSenseApp extends StatelessWidget {
  const FoodSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'FoodSense',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
    );
  }
}
