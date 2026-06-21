import 'dart:async';

import 'package:flutter/material.dart';

import '../Services/Firebase_service.dart';
import '../widgets/showdialog_warning.dart';

class FilterPage extends StatefulWidget {
  const FilterPage({
    super.key,
    required this.deviceId,
    required this.isConnected,
  });

  final String deviceId;
  final bool isConnected;

  @override
  State<FilterPage> createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  late final FirebaseService firebaseService;
  StreamSubscription<int>? _filterSubscription;
  int filterLife = 0;
  bool isResetting = false;

  @override
  void initState() {
    super.initState();
    firebaseService = FirebaseService(deviceId: widget.deviceId);
    if (widget.deviceId.isNotEmpty) {
      _filterSubscription = firebaseService.getFilterLifeStream().listen(
        (value) {
          if (mounted) setState(() => filterLife = value.clamp(0, 100));
        },
      );
    }
  }

  @override
  void dispose() {
    _filterSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 360;
    final image = filterLife <= 50
        ? 'assets/images/filterkotor.png'
        : 'assets/images/filterbersih.png';

    return DraggableScrollableSheet(
      initialChildSize: 0.56,
      minChildSize: 0.38,
      maxChildSize: 0.82,
      expand: false,
      builder: (context, scrollController) {
        return Material(
          color: Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: screenWidth.clamp(0.0, 600.0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 20,
              12,
              compact ? 14 : 20,
              28,
            ),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Umur Filter',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ),
                Image.asset(
                  image,
                  height: compact ? 120 : 160,
                  fit: BoxFit.contain,
                ),
                Row(
                  children: [
                    const Text('Kondisi filter'),
                    const Spacer(),
                    Text(
                      '$filterLife%',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 12,
                    value: filterLife / 100,
                    backgroundColor: Colors.grey[200],
                    color: filterLife <= 50 ? Colors.orange : Colors.lightGreen,
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Reset Filter',
                        style: TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                    ),
                    FilledButton(
                      onPressed: isResetting ? null : _resetFilter,
                      child: isResetting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Reset'),
                    ),
                  ],
                ),
              ],
            ),
          ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _resetFilter() async {
    if (!widget.isConnected || widget.deviceId.isEmpty) {
      showModernDialog(
        context: context,
        title: 'AirFresh Offline',
        message: 'Hubungkan perangkat sebelum melakukan reset filter.',
        icon: Icons.wifi_off_rounded,
        iconColor: Colors.redAccent,
      );
      return;
    }
    if (filterLife > 50) {
      showModernDialog(
        context: context,
        title: 'Filter Masih Baik',
        message: 'Umur filter masih $filterLife%. Reset tersedia saat nilainya 50% atau kurang.',
        icon: Icons.info_outline_rounded,
        iconColor: Colors.orange,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Reset'),
        content: const Text('Reset umur filter sekarang?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => isResetting = true);
    try {
      await firebaseService.resetFilterCommand(1);
      await Future<void>.delayed(const Duration(seconds: 1));
      await firebaseService.resetFilterCommand(0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perintah reset filter terkirim')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reset filter gagal: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => isResetting = false);
    }
  }
}
