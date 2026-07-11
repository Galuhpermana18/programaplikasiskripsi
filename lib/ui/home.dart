import 'package:flutter/material.dart';
import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../Services/Firebase_service.dart';
import '../Services/preferences.dart';
import '../utils/get_color_co2.dart';
import '../utils/get_color_pm10.dart';
import '../utils/get_color_pm25.dart';
import '../utils/get_color_tvoc.dart';
import '../connectedPage/Connected.dart';
import '../widgets/showdialog_warning.dart';
import 'DiamondMenuWidget.dart';
import 'filterpage.dart';

class HomePage extends StatefulWidget {
  final String deviceId;

  const HomePage({super.key, required this.deviceId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late FirebaseService firebaseService;
  StreamSubscription<Map<String, dynamic>>? sensorSubscription;
  StreamSubscription<ToggleStatus>? toggleSubscription;
  StreamSubscription<int>? filterSubscription;
  Timer? connectionTimer;
  DateTime? lastTimestampChange;
  String? lastSensorTimestamp;
  String? timeCategory;
  bool isConnected = false;
  String activeDeviceId = '';

  late PageController pageController;
  late AnimationController scaleAnimation;
  int pm25 = 0;
  int co2 = 0;
  double tvoc = 0;
  int pm10 = 0;
  double temperature = 0;
  double humidity = 0;
  int filterLife = 100;
  static const int _maxChartPoints = 20;
  final List<double> _pm25History = [];
  final List<double> _pm10History = [];
  final List<double> _co2History = [];
  final List<double> _tvocHistory = [];
  final List<String> _chartTimeLabels = [];
  int currentIndex = 0;
  bool isPowerOn = false;
  bool isPowerBusy = false;
  bool isFanModeAutomatic = false;
  bool isLocationLoading = false;
  String locationName = 'Mendeteksi lokasi...';

  List<Map<String, dynamic>> get sensorData => [
    {
      'title': 'PM2.5',
      'value': '$pm25',
      'unit': 'µg/m³',
      'color': getPmColor(pm25),
    },
    {
      'title': 'PM10',
      'value': '$pm10',
      'unit': 'µg/m³',
      'color': getPm10Color(pm10),
    },
    {
      'title': 'eCO₂',
      'value': '$co2',
      'unit': 'ppm',
      'color': getEco2Color(co2),
    },
    {
      'title': 'TVOC',
      'value': _sensorNumber(tvoc),
      'unit': 'ppb',
      'color': getTvocColor(tvoc),
    },
  ];

  Color get currentColor {
    return sensorData[currentIndex]['color'];
  }

  @override
  void initState() {
    super.initState();

    activeDeviceId = widget.deviceId;
    firebaseService = FirebaseService(deviceId: activeDeviceId);

    pageController = PageController();

    scaleAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      lowerBound: 0.95,
      upperBound: 1.05,
    )..repeat(reverse: true);

    timeCategory = _getTimeCategory();
    _loadCurrentLocation();
    _initializeDeviceData();
  }

  @override
  void dispose() {
    sensorSubscription?.cancel();
    toggleSubscription?.cancel();
    filterSubscription?.cancel();
    connectionTimer?.cancel();
    pageController.dispose();
    scaleAnimation.dispose();
    super.dispose();
  }

  Future<void> _initializeDeviceData() async {
    isFanModeAutomatic = await DeviceStorage.loadFanMode();
    isPowerOn = await DeviceStorage.loadPowerState();

    if (activeDeviceId.isEmpty) {
      activeDeviceId = await _resolveDeviceId();
      firebaseService = FirebaseService(deviceId: activeDeviceId);
    }

    if (mounted) setState(() {});

    if (activeDeviceId.isEmpty) {
      scaleAnimation.stop();
      return;
    }

    await _startDeviceDataListeners();
  }

  Future<void> _startDeviceDataListeners() async {
    if (!mounted || activeDeviceId.isEmpty) return;

    await sensorSubscription?.cancel();
    await filterSubscription?.cancel();
    await toggleSubscription?.cancel();
    connectionTimer?.cancel();
    lastSensorTimestamp = null;
    lastTimestampChange = null;
    _clearChartData();

    firebaseService = FirebaseService(deviceId: activeDeviceId);

    debugPrint(
      '[HOME] Memulai listener Firebase untuk device: $activeDeviceId',
    );
    _initializeNativeService();

    await airFreshDatabase.ref(firebaseService.sensorsPath).keepSynced(true);
    sensorSubscription = firebaseService.getSensorStream().listen(
      _handleSensorData,
      onError: (Object error) {
        debugPrint('[Firebase] Sensor stream error: $error');
        _setConnectionState(false);
      },
    );
    filterSubscription = firebaseService.getFilterLifeStream().listen(
      (value) {
        if (!mounted) return;
        setState(() => filterLife = value.clamp(0, 100));
      },
      onError: (Object error) {
        debugPrint('[Firebase] Filter stream error: $error');
      },
    );
    toggleSubscription = firebaseService.getToggleStream().listen(
      (status) {
        if (!mounted) return;
        final powerOn = status.swPower == 1;
        final automatic = status.mode == 1;
        setState(() {
          isPowerOn = powerOn;
          isFanModeAutomatic = automatic;
        });
        DeviceStorage.savePowerState(powerOn);
        DeviceStorage.saveFanMode(automatic);
      },
      onError: (Object error) {
        debugPrint('[Firebase] Control stream error: $error');
      },
    );

    connectionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final update = lastTimestampChange;
      final online =
          update != null &&
          DateTime.now().difference(update) <= const Duration(seconds: 5);
      _setConnectionState(online);
    });
  }

  Future<String> _resolveDeviceId() async {
    return await DeviceStorage.loadDeviceId() ?? '';
  }

  void _handleSensorData(Map<String, dynamic> data) {
    if (!mounted || data.isEmpty) {
      _setConnectionState(false);
      return;
    }

    final timestamp = data['timestamp']?.toString().trim();
    if (timestamp == null || timestamp.isEmpty) {
      debugPrint('[Sensor heartbeat] Timestamp kosong, perangkat offline.');
      _setConnectionState(false);
      return;
    }

    final now = DateTime.now();
    final timestampChanged = timestamp != lastSensorTimestamp;
    if (timestampChanged) {
      lastSensorTimestamp = timestamp;
      lastTimestampChange = now;
      debugPrint('[Sensor heartbeat] Timestamp berubah: $timestamp');
    }

    final timestampIsFresh =
        lastTimestampChange != null &&
        now.difference(lastTimestampChange!) <= const Duration(seconds: 5);
    if (!timestampIsFresh) {
      _setConnectionState(false);
      return;
    }

    final nextPm25 = _asDouble(data['pm25']).round();
    final nextPm10 = _asDouble(data['pm10']).round();
    final nextCo2 = _asDouble(data['co2']).round();
    final nextTvoc = _asDouble(data['tvoc']);

    setState(() {
      pm25 = nextPm25;
      pm10 = nextPm10;
      co2 = nextCo2;
      tvoc = nextTvoc;
      temperature = _asDouble(data['temperature'] ?? data['temp']);
      humidity = _asDouble(data['humidity'] ?? data['hum']);
      isConnected = true;

      if (timestampChanged) {
        _addChartReading(
          timestamp: timestamp,
          pm25Value: nextPm25.toDouble(),
          pm10Value: nextPm10.toDouble(),
          co2Value: nextCo2.toDouble(),
          tvocValue: nextTvoc,
        );
      }
    });
    if (!scaleAnimation.isAnimating) {
      scaleAnimation.repeat(reverse: true);
    }
  }

  double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }

  String _sensorNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }

  void _addChartReading({
    required String timestamp,
    required double pm25Value,
    required double pm10Value,
    required double co2Value,
    required double tvocValue,
  }) {
    if (_chartTimeLabels.length >= _maxChartPoints) {
      _chartTimeLabels.removeAt(0);
      _pm25History.removeAt(0);
      _pm10History.removeAt(0);
      _co2History.removeAt(0);
      _tvocHistory.removeAt(0);
    }

    _chartTimeLabels.add(timestamp.split(' ').last);
    _pm25History.add(pm25Value);
    _pm10History.add(pm10Value);
    _co2History.add(co2Value);
    _tvocHistory.add(tvocValue);
  }

  void _clearChartData() {
    _chartTimeLabels.clear();
    _pm25History.clear();
    _pm10History.clear();
    _co2History.clear();
    _tvocHistory.clear();
  }

  List<double> get _selectedChartHistory {
    if (currentIndex == 1) return _pm10History;
    if (currentIndex == 2) return _co2History;
    if (currentIndex == 3) return _tvocHistory;
    return _pm25History;
  }

  List<FlSpot> get _currentChartSpots {
    return _selectedChartHistory
        .asMap()
        .entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value))
        .toList(growable: false);
  }

  double get _currentChartMaxY {
    final history = _selectedChartHistory;
    if (history.isEmpty) return 100;

    var highest = history.first;
    for (final value in history.skip(1)) {
      if (value > highest) highest = value;
    }
    final paddedMaximum = highest * 1.2;
    return paddedMaximum < 10 ? 10 : paddedMaximum;
  }

  Widget _chartBottomTitle(double value) {
    final index = value.toInt();
    if (value != index.toDouble() ||
        index < 0 ||
        index >= _chartTimeLabels.length) {
      return const SizedBox.shrink();
    }

    final isVisible =
        index == 0 || index == _chartTimeLabels.length - 1 || index % 5 == 0;
    if (!isVisible) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        _chartTimeLabels[index],
        style: const TextStyle(
          color: Colors.black54,
          fontSize: 8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _setConnectionState(bool value) {
    if (!mounted) return;

    final sensorValuesNeedReset =
        !value &&
        (pm25 != 0 ||
            pm10 != 0 ||
            co2 != 0 ||
            tvoc != 0 ||
            temperature != 0 ||
            humidity != 0);
    if (isConnected == value && !sensorValuesNeedReset) return;

    final wasConnected = isConnected;
    setState(() {
      isConnected = value;
      if (!value) {
        pm25 = 0;
        pm10 = 0;
        co2 = 0;
        tvoc = 0;
        temperature = 0;
        humidity = 0;
      }
    });

    if (!value) {
      scaleAnimation.stop();
      if (wasConnected) {
        debugPrint(
          '[Sensor heartbeat] Timestamp tidak berubah selama 5 detik; '
          'data PM2.5, PM10, eCO₂, TVOC, suhu, dan kelembapan '
          'direset ke 0.',
        );
      }
    }
  }

  String _getTimeCategory() {
    final hour = DateTime.now().hour;

    if (hour >= 5 && hour < 10) {
      return 'Selamat Pagi';
    } else if (hour >= 10 && hour < 11) {
      return 'Selamat Pagi Menjelang Siang';
    } else if (hour >= 11 && hour < 14) {
      return 'Selamat Siang';
    } else if (hour >= 14 && hour < 15) {
      return 'Selamat Siang Menjelang Sore';
    } else if (hour >= 15 && hour < 17) {
      return 'Selamat Sore';
    } else if (hour >= 17 && hour < 18) {
      return 'Selamat Sore Menjelang Malam';
    } else {
      return 'Selamat Malam';
    }
  }

  Future<void> _loadCurrentLocation() async {
    setState(() {
      isLocationLoading = true;
      locationName = 'Mendeteksi lokasi...';
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _updateLocationName('Aktifkan lokasi HP');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _updateLocationName('Izin lokasi ditolak');
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _updateLocationName('Izin lokasi diblokir');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isEmpty) {
        _updateLocationName('Lokasi tidak ditemukan');
        return;
      }

      _updateLocationName(_formatLocationName(placemarks.first));
    } catch (error, stackTrace) {
      debugPrint('[Location] Gagal membaca lokasi: $error');
      debugPrintStack(stackTrace: stackTrace);
      _updateLocationName('Gagal membaca lokasi');
    }
  }

  void _updateLocationName(String value) {
    if (!mounted) return;

    setState(() {
      locationName = value;
      isLocationLoading = false;
    });
  }

  String _formatLocationName(Placemark placemark) {
    final area = _firstFilled([
      placemark.subLocality,
      placemark.locality,
      placemark.thoroughfare,
    ]);
    final city = _firstFilled([
      placemark.subAdministrativeArea,
      placemark.administrativeArea,
    ]);

    if (area == null && city == null) {
      return 'Lokasi saya';
    }

    final cleanArea = _cleanLocationPart(area);
    final cleanCity = _cleanLocationPart(city);

    if (cleanArea == null || cleanArea == cleanCity) {
      return cleanCity ?? 'Lokasi saya';
    }

    if (cleanCity == null) {
      return cleanArea;
    }

    return '$cleanArea, $cleanCity';
  }

  String? _firstFilled(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    return null;
  }

  String? _cleanLocationPart(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return trimmed
        .replaceAll('Kota Administrasi ', '')
        .replaceAll('Kota ', '')
        .replaceAll('Kabupaten ', '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final PmStatus status = isConnected
        ? getPmStatus(pm25)
        : const PmStatus('NULL', Colors.blue);
    final chartSpots = _currentChartSpots;
    final chartMaxY = _currentChartMaxY;
    final chartMaxX = chartSpots.length > 1
        ? (chartSpots.length - 1).toDouble()
        : 1.0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 360;
    final horizontalPadding = isCompact ? 16.0 : 20.0;
    final outerSensorSize = isCompact ? 180.0 : 210.0;
    final innerSensorSize = isCompact ? 132.0 : 146.0;
    final sensorAreaHeight = isCompact ? 240.0 : 270.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 130),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Hello, $timeCategory',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Have a fresh day',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.developer_board_rounded,
                                        size: 16,
                                        color: isConnected
                                            ? Colors.green
                                            : Colors.grey[600],
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          activeDeviceId.isNotEmpty
                                              ? activeDeviceId
                                              : 'Belum ada perangkat',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[700],
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 500),
                              child: Icon(
                                isConnected
                                    ? Icons.cloud_done_rounded
                                    : Icons.cloud_off_rounded,
                                key: ValueKey(isConnected),
                                color: isConnected ? Colors.green : Colors.red,
                                size: 28,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            const Text(
                              'Udara : ',
                              style: TextStyle(
                                fontSize: 15,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                            Text(
                              status.label,
                              style: TextStyle(
                                color: status.color,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(20),
                                      ),
                                    ),
                                    builder: (context) => ConnectPage(
                                      onDeviceConnected: _onDeviceConnected,
                                    ),
                                  );
                                },
                                child: _statusChip(
                                  context,
                                  Icons.bluetooth_searching_rounded,
                                  'Connect',
                                  Colors.purple,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: InkWell(
                                onTap: _showFilterSheet,
                                child: _statusChip(
                                  context,
                                  Icons.filter_alt,
                                  'Filter $filterLife%',
                                  Colors.blue,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: InkWell(
                                onTap: _showSettingsBottomSheet,
                                child: _statusChip(
                                  context,
                                  Icons.settings_rounded,
                                  'Settings',
                                  Colors.blue,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        InkWell(
                          onTap: _loadCurrentLocation,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.10),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.blue.withValues(alpha: 0.14),
                                  ),
                                  child: const Icon(
                                    Icons.location_on_rounded,
                                    color: Colors.blue,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Lokasi Saya',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 10,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        locationName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isLocationLoading)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.refresh_rounded,
                                    color: Colors.blue,
                                    size: 18,
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              height: sensorAreaHeight,
                              width: double.infinity,
                              child: Center(
                                child: AnimatedBuilder(
                                  animation: scaleAnimation,
                                  builder: (context, child) {
                                    return Transform.scale(
                                      scale: scaleAnimation.value,
                                      child: Container(
                                        width: outerSensorSize,
                                        height: outerSensorSize,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: currentColor.withValues(
                                            alpha: 0.25,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),

                            SizedBox(
                              width: innerSensorSize,
                              height: innerSensorSize,
                              child: PageView.builder(
                                controller: pageController,
                                itemCount: sensorData.length,
                                onPageChanged: (index) {
                                  setState(() {
                                    currentIndex = index;
                                  });
                                },
                                itemBuilder: (context, index) {
                                  final item = sensorData[index];

                                  return buildSensorCircle(
                                    item['title'],
                                    item['value'],
                                    item['unit'],
                                    item['color'],
                                    size: innerSensorSize,
                                  );
                                },
                              ),
                            ),

                            Positioned(
                              left: isCompact ? 4 : 10,
                              top: 8,
                              child: Column(
                                children: [
                                  const Text(
                                    'SPEED FAN',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Transform.scale(
                                    scale: isCompact ? 0.78 : 0.88,
                                    alignment: Alignment.topCenter,
                                    child: DiamondMenuWidget(
                                      deviceId: activeDeviceId,
                                      isConnected: isConnected,
                                      isPowerOn: isPowerOn,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),
                        SizedBox(
                          height: isCompact ? 112 : 120,
                          child: Row(
                            children: [
                              Expanded(
                                child: buildMiniSensorCard(
                                  icon: Icons.thermostat_rounded,
                                  title: 'Temperature',
                                  value: '${_sensorNumber(temperature)}°C',
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: buildMiniSensorCard(
                                  icon: Icons.water_drop_rounded,
                                  title: 'Humidity',
                                  value: '${_sensorNumber(humidity)}%',
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),

                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              sensorLabel('PM2.5', getPmColor(pm25), 0),
                              const SizedBox(width: 22),
                              sensorLabel('PM10', getPm10Color(pm10), 1),
                              const SizedBox(width: 22),
                              sensorLabel('eCO₂', getEco2Color(co2), 2),
                              const SizedBox(width: 22),
                              sensorLabel('TVOC', getTvocColor(tvoc), 3),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        SizedBox(
                          height: 190,
                          child: Stack(
                            children: [
                              LineChart(
                                LineChartData(
                                  minX: 0,
                                  maxX: chartMaxX,
                                  maxY: chartMaxY,
                                  minY: 0,

                                  gridData: const FlGridData(show: false),

                                  titlesData: FlTitlesData(
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        interval: chartMaxY / 5,
                                        reservedSize: 40,
                                        getTitlesWidget: (value, meta) {
                                          return Text(
                                            value.toInt().toString(),
                                            style: const TextStyle(
                                              color: Colors.black54,
                                              fontSize: 9,
                                            ),
                                          );
                                        },
                                      ),
                                    ),

                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        interval: 1,
                                        reservedSize: 34,
                                        getTitlesWidget: (value, meta) {
                                          return _chartBottomTitle(value);
                                        },
                                      ),
                                    ),

                                    rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),

                                    topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                  ),

                                  borderData: FlBorderData(show: false),

                                  lineBarsData: chartSpots.isEmpty
                                      ? const []
                                      : [
                                          LineChartBarData(
                                            spots: chartSpots,
                                            isCurved: true,
                                            curveSmoothness: 0.35,
                                            color: currentColor,
                                            barWidth: 3,
                                            isStrokeCapRound: true,
                                            dotData: const FlDotData(
                                              show: false,
                                            ),
                                            belowBarData: BarAreaData(
                                              show: true,
                                              color: currentColor.withValues(
                                                alpha: 0.08,
                                              ),
                                            ),
                                          ),
                                        ],
                                ),

                                duration: const Duration(milliseconds: 500),
                                curve: Curves.easeInOut,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomAppBar(
          color: Colors.blueAccent,
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          child: SizedBox(
            height: 65,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Text(
                  'AirFresh',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),

      floatingActionButton: SizedBox(
        width: 58,
        height: 58,
        child: FloatingActionButton(
          elevation: 6,
          backgroundColor: isPowerOn ? Colors.blue : Colors.redAccent,

          onPressed: isPowerBusy ? null : _sendPowerCommand,

          shape: const CircleBorder(),

          child: isPowerBusy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Icon(
                  Icons.power_settings_new,
                  color: Colors.white,
                  size: 30,
                ),
        ),
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Future<void> _initializeNativeService() async {
    try {
      const deviceChannel = MethodChannel('com.DLabs.air_fresh/device');
      await deviceChannel.invokeMethod<void>('setDeviceId', {
        'deviceId': activeDeviceId,
      });
      const serviceChannel = MethodChannel('start_service');
      await serviceChannel.invokeMethod<void>('startForegroundService');
    } on PlatformException catch (error) {
      debugPrint('[Native service] ${error.message}');
    }
  }

  Future<void> _onDeviceConnected(String deviceId) async {
    if (!mounted || deviceId.isEmpty) return;

    final normalizedDeviceId = deviceId.trim();
    setState(() {
      activeDeviceId = normalizedDeviceId;
      firebaseService = FirebaseService(deviceId: activeDeviceId);
    });

    final saved = await DeviceStorage.saveDeviceId(normalizedDeviceId);
    if (!saved) {
      debugPrint(
        '[HOME] Device ID gagal disimpan, tetapi listener tetap dijalankan.',
      );
    }

    await _startDeviceDataListeners();
  }

  void _showFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          FilterPage(deviceId: activeDeviceId, isConnected: isConnected),
    );
  }

  Future<void> _sendPowerCommand() async {
    if (!isConnected || activeDeviceId.isEmpty) {
      showModernDialog(
        context: context,
        title: 'AirFresh Offline',
        message: 'Hubungkan perangkat sebelum menggunakan tombol power.',
        icon: Icons.wifi_off_rounded,
        iconColor: Colors.redAccent,
      );
      return;
    }

    setState(() => isPowerBusy = true);
    final nextPowerState = !isPowerOn;
    try {
      await firebaseService.sendSWControlCommand(nextPowerState ? 1 : 0);
      await DeviceStorage.savePowerState(nextPowerState);
      if (mounted) setState(() => isPowerOn = nextPowerState);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Perintah power gagal: $error')));
      }
    } finally {
      if (mounted) setState(() => isPowerBusy = false);
    }
  }

  void _showSettingsBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.wifi_off_rounded,
                        color: Colors.blue,
                      ),
                      title: const Text('Lupakan Jaringan Device'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _forgetNetwork(sheetContext),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.ac_unit_rounded,
                        color: Colors.blue,
                      ),
                      title: const Text('Mode FAN'),
                      subtitle: Text(
                        isFanModeAutomatic ? 'Otomatis' : 'Manual',
                      ),
                      trailing: Switch(
                        value: isFanModeAutomatic,
                        onChanged: (value) async {
                          if (!isConnected || !isPowerOn) {
                            showModernDialog(
                              context: sheetContext,
                              title: !isConnected
                                  ? 'AirFresh Offline'
                                  : 'Power FAN',
                              message: !isConnected
                                  ? 'Hubungkan perangkat sebelum mengubah mode FAN.'
                                  : 'Aktifkan power sebelum mengubah mode FAN.',
                              icon: !isConnected
                                  ? Icons.wifi_off_rounded
                                  : Icons.power_settings_new_rounded,
                              iconColor: Colors.redAccent,
                            );
                            return;
                          }
                          try {
                            await firebaseService.sendModeCommand(
                              value ? 1 : 0,
                            );
                            await DeviceStorage.saveFanMode(value);
                            if (!mounted) return;
                            setState(() => isFanModeAutomatic = value);
                            setSheetState(() {});
                          } catch (error) {
                            if (sheetContext.mounted) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(
                                  content: Text('Mode FAN gagal: $error'),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.download_rounded,
                        color: Colors.blue,
                      ),
                      title: const Text('Unduh data kualitas udara'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _exportCsv(sheetContext),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _forgetNetwork(BuildContext sheetContext) async {
    if (activeDeviceId.isEmpty) {
      showModernDialog(
        context: sheetContext,
        title: 'Perangkat Belum Dipilih',
        message: 'Hubungkan atau pilih perangkat terlebih dahulu.',
        icon: Icons.bluetooth_disabled_rounded,
        iconColor: Colors.redAccent,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lupakan Jaringan Device'),
        content: const Text(
          'Perangkat akan restart dan kembali ke mode konfigurasi Bluetooth.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Lupakan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      // Pastikan perintah dimulai dari kondisi netral agar edge perintah terbaca.
      await firebaseService.sendBTControlCommand(0);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await firebaseService.sendBTControlCommand(1);
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      // Firmware juga mengembalikan nilai ke 0 sebelum restart. Ini fallback
      // agar perintah tidak tertinggal jika firmware terlambat membalas.
      try {
        await firebaseService.sendBTControlCommand(0);
      } catch (error) {
        debugPrint('[Forget network] Reset command sudah dikirim: $error');
      }

      await _disconnectActiveBluetoothDevice();
      try {
        const serviceChannel = MethodChannel('start_service');
        await serviceChannel.invokeMethod<void>('stopForegroundService');
      } on PlatformException catch (error) {
        debugPrint(
          '[Forget network] Gagal menghentikan service: ${error.message}',
        );
      }

      if (sheetContext.mounted) Navigator.pop(sheetContext);
      if (!mounted) return;

      debugPrint(
        '[Forget network] Perintah lupakan jaringan dikirim ke Firebase. '
        'Data WiFi tersimpan di aplikasi tetap dipertahankan.',
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const HomePage(deviceId: '')),
        (_) => false,
      );
    } catch (error) {
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(
          sheetContext,
        ).showSnackBar(SnackBar(content: Text('Perintah gagal: $error')));
      }
    }
  }

  Future<void> _disconnectActiveBluetoothDevice() async {
    final targetId = activeDeviceId.toLowerCase();

    for (final device in FlutterBluePlus.connectedDevices) {
      final deviceName = device.platformName.toLowerCase();
      final remoteId = device.remoteId.toString().toLowerCase();
      final isActiveDevice =
          deviceName == targetId ||
          remoteId == targetId ||
          deviceName.startsWith('airfresh_');

      if (!isActiveDevice) continue;

      try {
        await device.disconnect();
        debugPrint('[Bluetooth] Device diputus: ${device.platformName}');
      } catch (error) {
        debugPrint('[Bluetooth] Gagal disconnect: $error');
      }
    }
  }

  Future<void> _exportCsv(BuildContext sheetContext) async {
    try {
      const channel = MethodChannel('airfresh/csv');
      final result = await channel.invokeMethod<String>('exportCsv');
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          SnackBar(content: Text(result ?? 'Data berhasil diekspor')),
        );
      }
    } on PlatformException catch (error) {
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          SnackBar(content: Text(error.message ?? 'Ekspor data gagal')),
        );
      }
    }
  }

  Widget sensorLabel(String title, Color color, int index) {
    final bool active = currentIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          currentIndex = index;
        });

        pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      },
      child: Text(
        title,
        style: TextStyle(
          color: active ? color : color.withValues(alpha: 0.45),
          fontWeight: FontWeight.bold,
          fontFamily: 'Montserrat',
          fontSize: active ? 15 : 14,
        ),
      ),
    );
  }
}

Widget _statusChip(
  BuildContext context,
  IconData icon,
  String label,
  Color color,
) {
  final screenWidth = MediaQuery.of(context).size.width;

  return Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(
      horizontal: (screenWidth * 0.012).clamp(4.0, 6.0),
      vertical: 8,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withValues(alpha: 0.08)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: (screenWidth * 0.038).clamp(14.0, 17.0), color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: (screenWidth * 0.029).clamp(10.0, 12.0),
              fontWeight: FontWeight.w600,
              fontFamily: 'Montserrat',
            ),
          ),
        ),
      ],
    ),
  );
}

Widget buildSensorCircle(
  String title,
  String value,
  String unit,
  Color color, {
  double size = 150,
}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.1),
          blurRadius: 20,
          spreadRadius: 5,
        ),
      ],
    ),
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: (size * 0.13).clamp(17.0, 20.0),
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: (size * 0.27).clamp(34.0, 40.0),
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Montserrat',
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: (size * 0.105).clamp(13.0, 16.0),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget buildMiniSensorCard({
  required IconData icon,
  required String title,
  required String value,
  required Color color,
}) {
  return Container(
    height: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
          ),
          child: Icon(icon, color: color, size: 20),
        ),

        const SizedBox(height: 6),

        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
            fontFamily: 'Montserrat',
          ),
        ),

        const SizedBox(height: 3),

        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
            fontFamily: 'Montserrat',
          ),
        ),
      ],
    ),
  );
}
