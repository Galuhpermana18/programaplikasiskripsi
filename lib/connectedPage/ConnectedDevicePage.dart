import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../Services/preferences.dart';

class ConnectedDevicePage extends StatefulWidget {
  final String deviceName;
  final BluetoothDevice device;
  final BluetoothCharacteristic characteristic;
  final String deviceId;

  const ConnectedDevicePage({
    super.key,
    required this.deviceName,
    required this.device,
    required this.characteristic,
    required this.deviceId,
  });

  @override
  State<ConnectedDevicePage> createState() => _ConnectedDevicePageState();
}

class _ConnectedDevicePageState extends State<ConnectedDevicePage> {
  bool showCheckIcon = false;
  bool showErrorIcon = false;
  bool isLoading = false;
  bool _isDisposed = false;
  bool rememberWifi = false;
  bool isPasswordVisible = false;

  final TextEditingController ssidController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  StreamSubscription<List<int>>? _characteristicSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _validateAndSaveDeviceId();
    loadCurrentWifiSSID();
    loadSavedCredentials();
    monitorConnection();
    listenToCharacteristic();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _connectionSubscription?.cancel();
    _characteristicSubscription?.cancel();
    ssidController.dispose();
    passwordController.dispose();
    _safeDisconnect();
    super.dispose();
  }

  Future<void> _validateAndSaveDeviceId() async {
    if (widget.deviceId.isEmpty) {
      debugPrint('⚠️ [ERROR] deviceId is EMPTY!');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposed) {
          _showErrorSnackBar('Device ID tidak valid. Silakan scan ulang.');
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && !_isDisposed) Navigator.of(context).pop();
          });
        }
      });
      return;
    }

    debugPrint('🔵 [INIT] Saving Device ID: ${widget.deviceId}');

    try {
      bool saved = false;
      for (int attempt = 1; attempt <= 3 && !saved; attempt++) {
        saved = await DeviceStorage.saveDeviceId(widget.deviceId);

        if (saved) {
          debugPrint(
            '✅ [INIT] Device ID saved successfully (attempt $attempt)',
          );

          await Future.delayed(const Duration(milliseconds: 100));
          String? verified = await DeviceStorage.loadDeviceId();

          if (verified == widget.deviceId) {
            debugPrint('✅ [INIT] Device ID verified: $verified');
            break;
          } else {
            debugPrint(
              '⚠️ [INIT] Verification failed. Saved: $verified, Expected: ${widget.deviceId}',
            );
            saved = false;
          }
        } else {
          debugPrint('❌ [INIT] Failed to save Device ID (attempt $attempt)');
          if (attempt < 3) {
            await Future.delayed(Duration(milliseconds: 200 * attempt));
          }
        }
      }

      if (!saved) {
        debugPrint(
          '❌ [INIT] CRITICAL: Failed to save Device ID after 3 attempts!',
        );
        if (mounted && !_isDisposed) {
          _showErrorSnackBar('Gagal menyimpan Device ID. Coba lagi.');
        }
      }
    } catch (e) {
      debugPrint('❌ [INIT] Exception saving Device ID: $e');
    }
  }

  Future<void> loadCurrentWifiSSID() async {
    try {
      final info = NetworkInfo();
      String? wifiName = await info.getWifiName();

      if (wifiName != null && mounted && !_isDisposed) {
        wifiName = wifiName.replaceAll('"', '');

        _safeSetState(() {
          ssidController.text = wifiName!;
        });

        debugPrint('[WIFI] Current WiFi SSID: $wifiName');
      } else {
        debugPrint('[WIFI] No WiFi connected or permission denied');
      }
    } catch (e) {
      debugPrint('[WIFI] Error getting WiFi SSID: $e');
    }
  }

  Future<void> _safeDisconnect() async {
    try {
      final state = await widget.device.connectionState.first.timeout(
        const Duration(seconds: 2),
        onTimeout: () => BluetoothConnectionState.disconnected,
      );
      if (state == BluetoothConnectionState.connected) {
        await widget.device.disconnect().timeout(
          const Duration(seconds: 3),
          onTimeout: () => debugPrint('Disconnect timeout'),
        );
        debugPrint('✓ Device disconnected successfully');
      }
    } catch (e) {
      debugPrint('Failed to disconnect: $e');
    }
  }

  void monitorConnection() {
    _connectionSubscription = widget.device.connectionState.listen((
      BluetoothConnectionState state,
    ) {
      debugPrint('[BLE] Connection state: $state');
      if (state == BluetoothConnectionState.disconnected) {
        if (mounted && !_isDisposed) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_isDisposed) Navigator.of(context).pop();
          });
        }
      }
    });
  }

  void listenToCharacteristic() async {
    try {
      if (widget.characteristic.properties.notify ||
          widget.characteristic.properties.indicate) {
        await widget.characteristic.setNotifyValue(true);
        await Future.delayed(const Duration(milliseconds: 300));

        _characteristicSubscription = widget.characteristic.lastValueStream
            .listen(
              (value) {
                if (value.isNotEmpty && mounted && !_isDisposed) {
                  String response = utf8.decode(value);
                  debugPrint('Response: $response');

                  if (response.contains('OK') || response.contains('SUCCESS')) {
                    _safeSetState(() {
                      showCheckIcon = true;
                      showErrorIcon = false;
                    });
                  } else if (response.contains('ERROR') ||
                      response.contains('FAIL')) {
                    _safeSetState(() {
                      showErrorIcon = true;
                      showCheckIcon = false;
                    });
                  }
                }
              },
              onError: (error) {
                debugPrint('Characteristic listener: $error');
              },
            );
      }
    } catch (e) {
      debugPrint('Setting up listener: $e');
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) setState(fn);
  }

  void _showErrorSnackBar(String message) {
    if (mounted && !_isDisposed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 16.0,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> loadSavedCredentials() async {
    final credentials = await DeviceStorage.loadWifiCredentials();
    if (credentials != null && mounted && !_isDisposed) {
      _safeSetState(() {
        if (ssidController.text.isEmpty) {
          ssidController.text = credentials['ssid'] ?? '';
        }
        passwordController.text = credentials['password'] ?? '';
        rememberWifi = credentials['remember'] ?? false;
      });
      debugPrint('Loaded saved credentials: ${credentials['ssid']}');
    }
  }

  void handleSwitchChanged(bool value) {
    _safeSetState(() => rememberWifi = value);

    if (value) {
      if (ssidController.text.isNotEmpty &&
          passwordController.text.isNotEmpty) {
        DeviceStorage.saveWifiCredentials(
          ssidController.text,
          passwordController.text,
        );
      }
    } else {
      DeviceStorage.saveWifiCredentials('', '');
    }
  }

  Future<void> sendDataToDevice(String ssid, String password) async {
    if (_isDisposed || !mounted) return;

    _safeSetState(() {
      isLoading = true;
      showCheckIcon = false;
      showErrorIcon = false;
    });

    try {
      var connectionState = await widget.device.connectionState.first.timeout(
        const Duration(seconds: 2),
        onTimeout: () => BluetoothConnectionState.disconnected,
      );

      if (connectionState != BluetoothConnectionState.connected) {
        throw Exception('Device tidak terhubung');
      }

      String data = '$ssid|||$password';
      List<int> encodedData = utf8.encode(data);
      bool sent = false;

      for (int i = 0; i < 3 && !sent && mounted && !_isDisposed; i++) {
        try {
          await widget.characteristic.write(
            encodedData,
            withoutResponse: false,
            timeout: 10,
          );
          sent = true;
          debugPrint('✓ WiFi sent successfully (attempt ${i + 1})');
        } catch (e) {
          debugPrint('Retry attempt ${i + 1} failed: $e');
          if (i < 2)
            await Future.delayed(Duration(seconds: i + 1));
          else
            rethrow;
        }
      }

      if (!mounted || _isDisposed) return;

      String? savedId = await DeviceStorage.loadDeviceId();
      debugPrint('✅ Device ID verified after WiFi send: $savedId');

      if (savedId != widget.deviceId) {
        debugPrint('⚠️ Device ID mismatch! Re-saving...');
        await DeviceStorage.saveDeviceId(widget.deviceId);
      }

      _safeSetState(() {
        showCheckIcon = true;
        showErrorIcon = false;
        isLoading = false;
      });

      Future.delayed(const Duration(seconds: 3), () {
        _safeSetState(() => showCheckIcon = false);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'WiFi credentials dikirim ke $ssid',
                  style: const TextStyle(
                    fontSize: 16.0,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && !_isDisposed) _showRestartInfoDialog();
      });
    } catch (e) {
      debugPrint('Failed to send data: $e');

      _safeSetState(() {
        showErrorIcon = true;
        showCheckIcon = false;
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Gagal mengirim: ${e.toString()}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );

      Future.delayed(const Duration(seconds: 3), () {
        _safeSetState(() => showErrorIcon = false);
      });
    }
  }

  // ✅ PERBAIKAN: Langsung navigate ke Home.dart dengan passing Device ID
  void _showRestartInfoDialog() {
    if (!mounted || _isDisposed) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 10),
              Text('Informasi'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Device akan restart untuk menghubungkan ke WiFi.\n\n'
                'Aplikasi akan membuka halaman utama.',
                style: TextStyle(fontSize: 15, fontFamily: 'Montserrat'),
              ),
              const SizedBox(height: 10),
              Text(
                'Device ID: ${widget.deviceId}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontFamily: 'Montserrat',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                debugPrint('🔵 [DIALOG] Final verification...');
                String? finalCheck = await DeviceStorage.loadDeviceId();

                if (finalCheck == null || finalCheck.isEmpty) {
                  debugPrint('❌ [DIALOG] Device ID is null, saving now...');
                  bool saved = await DeviceStorage.saveDeviceId(
                    widget.deviceId,
                  );
                  if (saved) {
                    await Future.delayed(const Duration(milliseconds: 200));
                    finalCheck = await DeviceStorage.loadDeviceId();
                  }
                }

                debugPrint('✅ [DIALOG] Final Device ID: $finalCheck');

                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                await Future.delayed(const Duration(milliseconds: 300));

                if (mounted && !_isDisposed) Navigator.of(context).pop();
                await Future.delayed(const Duration(milliseconds: 300));

                // ✅ LANGSUNG KE HOME.DART DENGAN PASSING DEVICE ID
                if (mounted && !_isDisposed) {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/home',
                    (route) => false,
                    arguments: {
                      'deviceId': widget.deviceId,
                    }, // ✅ PASSING DEVICE ID
                  );
                  debugPrint(
                    '✅ [DIALOG] Navigate to Home with Device ID: ${widget.deviceId}',
                  );
                }
              },
              child: const Text('OK', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
              width: screenWidth.clamp(0.0, 600.0),
              padding: EdgeInsets.all(screenWidth < 360 ? 14 : 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  children: [
                    Container(
                      width: 50,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.bluetooth_connected,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.deviceName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontFamily: 'Montserrat',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (widget.deviceId.isNotEmpty)
                                Text(
                                  'ID: ${widget.deviceId}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Konfigurasi WiFi',
                        style: TextStyle(
                          fontSize: 20,
                          fontFamily: 'Montserrat',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: ssidController,
                      decoration: InputDecoration(
                        labelText: 'SSID',
                        prefixIcon: const Icon(Icons.wifi, color: Colors.blue),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.blue),
                          onPressed: loadCurrentWifiSSID,
                          tooltip: 'Refresh WiFi SSID',
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: passwordController,
                      obscureText: !isPasswordVisible,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock, color: Colors.blue),
                        suffixIcon: IconButton(
                          icon: Icon(
                            isPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.blue,
                          ),
                          onPressed: () {
                            _safeSetState(() {
                              isPasswordVisible = !isPasswordVisible;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Ingat WiFi ini?',
                          style: TextStyle(
                            fontSize: 16.0,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                        Switch(
                          value: rememberWifi,
                          activeColor: Colors.blue,
                          onChanged: handleSwitchChanged,
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          elevation: 3,
                        ),
                        onPressed: isLoading
                            ? null
                            : () async {
                                final ssid = ssidController.text.trim();
                                final password = passwordController.text.trim();

                                if (ssid.isEmpty || password.isEmpty) {
                                  _showErrorSnackBar(
                                    'SSID dan Password tidak boleh kosong',
                                  );
                                  return;
                                }
                                await sendDataToDevice(ssid, password);
                                if (rememberWifi) {
                                  await DeviceStorage.saveWifiCredentials(
                                    ssid,
                                    password,
                                  );
                                }
                              },
                        child: isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Konek Wifi',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (showCheckIcon)
                      const Column(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 60,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Berhasil terkirim!',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    if (showErrorIcon)
                      const Column(
                        children: [
                          Icon(Icons.error, color: Colors.red, size: 60),
                          SizedBox(height: 10),
                          Text(
                            'Gagal mengirim',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
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
      ),
    );
  }
}
