import 'package:flutter/material.dart';
import 'package:friends_game_app/core/widgets/app_logo.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: BrandColors.navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 72, light: true, vertical: true),
            SizedBox(height: 32),
            SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: BrandColors.gold)),
          ],
        ),
      ),
    );
  }
}
