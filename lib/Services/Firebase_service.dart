import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class ToggleStatus {
  final int btControl;
  final int swPower;
  final int mode;
  final int speed;
  final int resetFilter;

  const ToggleStatus({
    this.btControl = 0,
    this.swPower = 0,
    this.mode = 0,
    this.speed = 0,
    this.resetFilter = 0,
  });

  factory ToggleStatus.fromMap(Map<dynamic, dynamic> map) {
    return ToggleStatus(
      btControl: _asInt(map['btcontrol'] ?? map['BTcontrol']),
      swPower: _asInt(map['swpower'] ?? map['SWpower']),
      mode: _asInt(map['mode'] ?? map['Mode']),
      speed: _asInt(map['speed'] ?? map['Speed']),
      resetFilter: _asInt(map['resetfilter'] ?? map['Resetfilter']),
    );
  }

  Map<String, dynamic> toMap() => {
    'btcontrol': btControl,
    'swpower': swPower,
    'mode': mode,
    'speed': speed,
    'resetfilter': resetFilter,
  };

  static int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

class FirebaseService {
  FirebaseService({required this.deviceId});

  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final String deviceId;

  String get sensorsPath => 'Devices/$deviceId/sensors';
  String get controlPath => 'Devices/$deviceId/Control';

  Future<ToggleStatus> getToggleStatus() async {
    final snapshot = await _database.ref(controlPath).get();
    final value = snapshot.value;
    if (value is! Map) return const ToggleStatus();
    return ToggleStatus.fromMap(value);
  }

  Stream<ToggleStatus> getToggleStream() {
    return _database.ref(controlPath).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return const ToggleStatus();
      return ToggleStatus.fromMap(value);
    });
  }

  Stream<Map<String, dynamic>> getSensorStream() {
    return _database.ref(sensorsPath).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(value);
    });
  }

  Stream<int> getFilterLifeStream() {
    return _database.ref('$sensorsPath/filterlife').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? 0;
    });
  }

  Future<void> sendSWControlCommand(int value) =>
      _safeWrite('$controlPath/swpower', value, 'power');

  Future<void> sendBTControlCommand(int value) =>
      _safeWrite('$controlPath/btcontrol', value, 'bluetooth');

  Future<void> sendModeCommand(int value) =>
      _safeWrite('$controlPath/mode', value, 'mode');

  Future<void> sendSpeedCommand(int value) =>
      _safeWrite('$controlPath/speed', value, 'speed');

  Future<void> resetFilterCommand(int value) =>
      _safeWrite('$controlPath/resetfilter', value, 'reset filter');

  Future<void> _safeWrite(
    String path,
    dynamic value,
    String label, {
    int retryCount = 3,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= retryCount; attempt++) {
      try {
        await _database.ref(path).set(value);
        return;
      } catch (error) {
        lastError = error;
        if (kDebugMode) {
          debugPrint('[Firebase] $label gagal ($attempt/$retryCount): $error');
        }
        if (attempt < retryCount) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    throw StateError('Gagal mengirim $label ke Firebase: $lastError');
  }
}
