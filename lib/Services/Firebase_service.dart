import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

const String airFreshDatabaseUrl =
    'https://airfreshskripsi-default-rtdb.asia-southeast1.firebasedatabase.app/';

FirebaseDatabase get airFreshDatabase => FirebaseDatabase.instanceFor(
  app: Firebase.app(),
  databaseURL: airFreshDatabaseUrl,
);

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
  FirebaseService({required String deviceId}) : deviceId = deviceId.trim() {
    if (kDebugMode) {
      if (this.deviceId.isEmpty) {
        debugPrint(
          '[Firebase] Device ID kosong. Menunggu perangkat terhubung melalui BLE.',
        );
      } else {
        debugPrint('[Firebase] Device ID: ${this.deviceId}');
        debugPrint('[Firebase] Path sensor: $sensorsPath');
      }
    }
  }

  final FirebaseDatabase _database = airFreshDatabase;
  final String deviceId;

  String get sensorsPath => 'Devices/$deviceId/sensors';
  String get filterLifePath => 'Devices/$deviceId/filter/filterlife';
  String get controlPath => 'Devices/$deviceId/Control';
  String get speedPath => '$controlPath/speed';

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
    if (deviceId.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[Firebase] Pembacaan sensor dibatalkan karena Device ID kosong.',
        );
      }
      return const Stream<Map<String, dynamic>>.empty();
    }

    final sensorReference = _database.ref(sensorsPath);

    if (kDebugMode) {
      debugPrint('[Firebase] Mulai membaca sensor: $sensorsPath');
    }

    return sensorReference.onValue
        .map((event) {
          final value = event.snapshot.value;
          if (value is! Map) {
            if (kDebugMode) {
              debugPrint(
                '[Firebase] Data sensor kosong/tidak valid pada $sensorsPath: $value',
              );
            }
            return <String, dynamic>{};
          }

          final sensorData = Map<String, dynamic>.from(value);
          if (kDebugMode) {
            debugPrint('[Firebase] Data sensor diterima dari $sensorsPath');
            debugPrint('[Firebase] Sensor: $sensorData');
          }
          return sensorData;
        })
        .handleError((Object error, StackTrace stackTrace) {
          if (kDebugMode) {
            debugPrint('[Firebase] Gagal membaca $sensorsPath: $error');
          }
        });
  }

  Stream<int> getFilterLifeStream() {
    return _database.ref(filterLifePath).onValue.map((event) {
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
      _safeWrite(speedPath, value, 'speed');

  Future<void> resetFilterCommand(int value) =>
      _safeWrite('$controlPath/resetfilter', value, 'reset filter');

  Future<void> _safeWrite(
    String path,
    dynamic value,
    String label, {
    int retryCount = 3,
  }) async {
    if (deviceId.isEmpty) {
      throw StateError('Device ID kosong. Penulisan $label dibatalkan.');
    }

    Object? lastError;
    for (var attempt = 1; attempt <= retryCount; attempt++) {
      try {
        if (kDebugMode) {
          debugPrint('[Firebase] Menulis $label ke $path = $value');
        }
        await _database.ref(path).set(value);
        if (kDebugMode) {
          debugPrint('[Firebase] $label berhasil ditulis ke $path');
        }
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
