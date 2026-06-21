import 'dart:async';

import 'package:flutter/material.dart';

import '../services/preferences.dart';
import 'home.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? deviceId;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    loadDeviceId();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> loadDeviceId() async {
    try {
      final savedDeviceId = await DeviceStorage.loadDeviceId();

      if (!mounted) return;
      setState(() {
        deviceId = savedDeviceId;
      });

      debugPrint('[SPLASH] Device ID loaded: $deviceId');
      startTimer();
    } catch (e) {
      debugPrint('[SPLASH] Error loading device ID: $e');
      startTimer();
    }
  }

  void startTimer() {
    _timer = Timer(const Duration(seconds: 3), navigateToHome);
  }

  void navigateToHome() {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => HomePage(deviceId: deviceId ?? ''),
      ),
    );

    debugPrint(
      '[SPLASH] Navigating to homepage with deviceId: ${deviceId ?? "empty"}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF06131F) : Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shortestSide = constraints.maxWidth < constraints.maxHeight
                ? constraints.maxWidth
                : constraints.maxHeight;
            final logoSize = (shortestSide * 0.45).clamp(120.0, 190.0);
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/app_icon.png',
                width: logoSize,
                height: logoSize,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 18),
              const Text(
                'AirFresh',
                style: TextStyle(
                  color: Color(0xFF2EA8E5),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 42),
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2EA8E5)),
                ),
              ),
            ],
          ),
              ),
            );
          },
        ),
      ),
    );
  }
}
