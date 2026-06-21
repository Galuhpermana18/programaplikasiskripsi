import 'dart:async';

import 'package:flutter/material.dart';

import '../Services/Firebase_service.dart';
import '../widgets/showdialog_warning.dart';

class DiamondMenuWidget extends StatefulWidget {
  const DiamondMenuWidget({
    super.key,
    required this.deviceId,
    required this.isConnected,
    required this.isPowerOn,
  });

  final String deviceId;
  final bool isConnected;
  final bool isPowerOn;

  @override
  State<DiamondMenuWidget> createState() => DiamondMenuWidgetState();
}

class DiamondMenuWidgetState extends State<DiamondMenuWidget> {
  late final FirebaseService firebaseService;
  StreamSubscription<ToggleStatus>? _toggleSubscription;
  bool isMenuOpen = false;
  String? selectedLevel;

  @override
  void initState() {
    super.initState();
    firebaseService = FirebaseService(deviceId: widget.deviceId);
    if (widget.deviceId.isNotEmpty) {
      _toggleSubscription = firebaseService.getToggleStream().listen((status) {
        if (!mounted) return;
        final level = switch (status.speed) {
          1 => 'low',
          2 => 'medium',
          3 => 'high',
          _ => null,
        };
        setState(() => selectedLevel = widget.isPowerOn ? level : null);
      });
    }
  }

  @override
  void didUpdateWidget(covariant DiamondMenuWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPowerOn && !widget.isPowerOn && selectedLevel != null) {
      setState(() => selectedLevel = null);
    }
  }

  @override
  void dispose() {
    _toggleSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 180,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => isMenuOpen = !isMenuOpen),
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Transform.rotate(
                    angle: -0.785398,
                    child: const Icon(Icons.speed, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: isMenuOpen
                ? Column(
                    key: const ValueKey('speed-menu'),
                    children: [
                      _menuItem('Low', 'low', Colors.green, 1),
                      _menuItem('Medium', 'medium', Colors.orange, 2),
                      _menuItem('High', 'high', Colors.red, 3),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('speed-closed')),
          ),
        ],
      ),
    );
  }

  Widget _menuItem(String text, String level, Color color, int speed) {
    final isSelected = selectedLevel == level;
    return GestureDetector(
      onTap: () => _selectSpeed(level, speed),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.blue,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black12)],
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Future<void> _selectSpeed(String level, int speed) async {
    if (!widget.isConnected || widget.deviceId.isEmpty) {
      showModernDialog(
        context: context,
        title: 'AirFresh Offline',
        message: 'Perangkat belum terhubung. Hubungkan perangkat terlebih dahulu.',
        icon: Icons.wifi_off_rounded,
        iconColor: Colors.redAccent,
      );
      return;
    }
    if (!widget.isPowerOn) {
      showModernDialog(
        context: context,
        title: 'Power FAN',
        message: 'FAN sedang OFF. Aktifkan power sebelum mengubah kecepatan.',
        icon: Icons.power_settings_new_rounded,
        iconColor: Colors.redAccent,
      );
      return;
    }

    try {
      await firebaseService.sendSpeedCommand(speed);
      if (mounted) setState(() => selectedLevel = level);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengubah kecepatan: $error')),
      );
    }
  }
}
