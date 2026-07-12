import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../Services/preferences.dart';
import 'ConnectedDevicePage.dart';

const String _airFreshServiceUuid = '5fcf4517-a37c-4c06-a5d0-d25ec3991ec7';
const String _airFreshCharacteristicUuid =
    'deb5483e-36e1-1991-b7f5-ea19941b17a2';
const MethodChannel _androidChannel = MethodChannel(
  'com.DLabs.air_fresh/android',
);

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, this.onDeviceConnected});

  final ValueChanged<String>? onDeviceConnected;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  bool _isScanning = false;
  List<ScanResult> scanResultList = [];
  BluetoothCharacteristic? characteristic;
  BluetoothDevice? connectedDevice;

  bool isBluetoothEnabled = false;
  bool isDialogShowing = false;

  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _stopScan();
    _adapterStateSubscription?.cancel();
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    final permissionsGranted = await _requestPermissions();
    if (!permissionsGranted || !mounted) return;
    await _checkAndEnableBluetooth();
    _initBle();
  }

  Future<List<Permission>> _requiredBlePermissions() async {
    try {
      final sdkInt = await _androidChannel.invokeMethod<int>('getSdkInt') ?? 31;
      return sdkInt >= 31
          ? <Permission>[Permission.bluetoothScan, Permission.bluetoothConnect]
          : <Permission>[Permission.location];
    } on PlatformException {
      return <Permission>[
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ];
    }
  }

  Future<bool> _requestPermissions() async {
    final requiredPermissions = await _requiredBlePermissions();
    final statuses = await requiredPermissions.request();

    for (var entry in statuses.entries) {
      if (!entry.value.isGranted) {
        _showPermissionDialog(entry.key);
        return false;
      }
    }
    debugPrint('All permissions granted');
    return true;
  }

  void _showPermissionDialog(Permission permission) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izin Diperlukan'),
        content: Text(
          'Izin ${_getPermissionName(permission)} diperlukan untuk scan perangkat BLE.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Buka Pengaturan'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
  }

  String _getPermissionName(Permission permission) {
    switch (permission) {
      case Permission.location:
        return 'Lokasi';
      case Permission.bluetoothScan:
        return 'Bluetooth Scan';
      case Permission.bluetoothConnect:
        return 'Bluetooth Connect';
      default:
        return permission.toString();
    }
  }

  void _initBle() {
    // Listen adapter state
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      bool isOn = state == BluetoothAdapterState.on;
      if (isBluetoothEnabled != isOn) {
        setState(() => isBluetoothEnabled = isOn);
      }

      if (!isOn && !isDialogShowing) {
        _showBluetoothDialog();
      }
    });

    // Listen scanning state
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((isScanning) {
      if (!mounted) return;
      setState(() => _isScanning = isScanning);
    });
  }

  Future<void> _checkAndEnableBluetooth() async {
    var adapterState = await FlutterBluePlus.adapterState.first;
    isBluetoothEnabled = adapterState == BluetoothAdapterState.on;
    if (!isBluetoothEnabled && mounted) _showBluetoothDialog();
  }

  void _showBluetoothDialog() {
    if (!mounted || isDialogShowing) return;
    isDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Bluetooth Tidak Aktif'),
        content: const Text('Aktifkan Bluetooth untuk menggunakan aplikasi'),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await FlutterBluePlus.turnOn();
              } catch (_) {}
              if (context.mounted) Navigator.pop(context);
              isDialogShowing = false;
            },
            child: const Text('Aktifkan'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              isDialogShowing = false;
            },
            child: const Text('Batal'),
          ),
        ],
      ),
    );
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanResultsSubscription?.cancel();
      _scanResultsSubscription = null;
    } catch (e) {
      debugPrint('Stop scan error: $e');
    }
  }

  Future<void> scan() async {
    if (!mounted) return;
    if (!await _requestPermissions()) return;

    if (!isBluetoothEnabled) {
      _showBluetoothDialog();
      return;
    }

    if (_isScanning) {
      await _stopScan();
      if (mounted) setState(() => _isScanning = false);
      return;
    }

    setState(() {
      _isScanning = true;
      scanResultList.clear();
    });

    _scanResultsSubscription?.cancel();
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;

      final filtered = results.where((r) {
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName;
        debugPrint('Found device: $name');
        return name.toUpperCase().startsWith('AIRFRESH_');
      }).toList()..sort((a, b) => b.rssi.compareTo(a.rssi));

      setState(() => scanResultList = filtered);
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: <Guid>[Guid(_airFreshServiceUuid)],
        timeout: const Duration(seconds: 10),
      );
      await Future.delayed(const Duration(seconds: 10));
      await _stopScan();
      if (mounted) setState(() => _isScanning = false);

      if (scanResultList.isEmpty) {
        _showErrorDialog(
          'Tidak Ada Perangkat',
          'Tidak ditemukan perangkat. Pastikan perangkat dalam mode pairing.',
        );
      }
    } catch (e) {
      debugPrint('Scan error: $e');
      if (mounted) {
        _showErrorDialog('Scanning Error', e.toString());
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await device.connect(
        license: License.free,
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      final services = await device.discoverServices();
      for (var service in services) {
        for (var char in service.characteristics) {
          if (char.uuid.toString().toLowerCase() ==
              _airFreshCharacteristicUuid) {
            characteristic = char;
            await char.setNotifyValue(true);

            if (!mounted) return;
            Navigator.pop(context);

            String deviceId = device.platformName.isNotEmpty
                ? device.platformName
                : device.remoteId.toString();

            await DeviceStorage.saveDeviceId(deviceId);
            if (!mounted) return;
            widget.onDeviceConnected?.call(deviceId);

            Navigator.pushReplacement(
              context,
              PageRouteBuilder<void>(
                opaque: false,
                barrierColor: Colors.black.withValues(alpha: 0.35),
                barrierDismissible: false,
                transitionDuration: const Duration(milliseconds: 250),
                reverseTransitionDuration: const Duration(milliseconds: 200),
                pageBuilder: (_, _, _) => ConnectedDevicePage(
                  deviceName: device.platformName.isNotEmpty
                      ? device.platformName
                      : 'Unknown Device',
                  device: device,
                  characteristic: characteristic!,
                  deviceId: deviceId,
                ),
                transitionsBuilder: (_, animation, _, child) {
                  final position = Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  );
                  return SlideTransition(position: position, child: child);
                },
              ),
            );
            return;
          }
        }
      }

      Navigator.pop(context);
      _showErrorDialog('Koneksi Gagal', 'Karakteristik tidak ditemukan.');
      await device.disconnect();
    } catch (e) {
      Navigator.pop(context);
      _showErrorDialog('Koneksi Gagal', e.toString());
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget buildDeviceListItem(ScanResult r) {
    String name = r.device.platformName.isNotEmpty
        ? r.device.platformName
        : (r.advertisementData.advName.isNotEmpty
              ? r.advertisementData.advName
              : 'Unknown Device');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 2,
      child: ListTile(
        onTap: () => connectToDevice(r.device),
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withOpacity(0.1),
          child: Image.asset(
            'assets/images/bleicon.png',
            width: 40,
            height: 40,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.bluetooth, color: Colors.blue),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          r.device.remoteId.toString(),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.signal_cellular_alt,
              color: _getSignalColor(r.rssi),
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              '${r.rssi} dBm',
              style: TextStyle(
                fontSize: 12,
                color: _getSignalColor(r.rssi),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getSignalColor(int rssi) {
    if (rssi >= -60) return Colors.green;
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 360;
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: screenWidth.clamp(0.0, 600.0),
          padding: EdgeInsets.all(compact ? 14 : 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Scan Perangkat',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isScanning ? Colors.red : Colors.blue,
                    ),
                    onPressed: scan,
                    icon: Icon(
                      _isScanning ? Icons.stop : Icons.search,
                      size: 20,
                    ),
                    label: Text(_isScanning ? 'Stop' : 'Scan'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (!_isScanning && scanResultList.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Ditemukan perangkat',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ),
              Expanded(
                child: _isScanning && scanResultList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: compact ? 72 : 92,
                              height: compact ? 72 : 92,
                              child: const CircularProgressIndicator(
                                strokeWidth: 5,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Mencari perangkat...',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : scanResultList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.bluetooth_searching,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Tidak ada perangkat ditemukan',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tekan tombol Scan untuk memulai',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: scanResultList.length,
                        itemBuilder: (context, index) =>
                            buildDeviceListItem(scanResultList[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
