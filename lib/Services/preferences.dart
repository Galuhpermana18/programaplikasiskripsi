import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class DeviceStorage {
  static const String _keyDeviceId = 'device_id';
  static const String _keySavedSsid = 'saved_ssid';
  static const String _keySavedPassword = 'saved_password';
  static const String _keyRememberWifi = 'remember_wifi';
  static const String _keyFanMode = 'fan_mode_switch';
  static const String _keyPowerState = 'power_state';
  static Future<bool> saveDeviceId(String deviceId) async {
    final normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty) {
      debugPrint('[DeviceStorage] Device ID kosong, penyimpanan dibatalkan.');
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(_keyDeviceId, normalizedDeviceId);
      debugPrint(
        '[DeviceStorage] Device ID ${saved ? "tersimpan" : "gagal disimpan"}: '
        '$normalizedDeviceId',
      );
      return saved;
    } catch (error) {
      debugPrint('[DeviceStorage] Gagal menyimpan Device ID: $error');
      return false;
    }
  }

  static Future<String?> loadDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString(_keyDeviceId)?.trim();
      if (deviceId == null || deviceId.isEmpty) {
        debugPrint('[DeviceStorage] Belum ada Device ID yang tersimpan.');
        return null;
      }
      debugPrint('[DeviceStorage] Device ID dimuat: $deviceId');
      return deviceId;
    } catch (error) {
      debugPrint('[DeviceStorage] Gagal memuat Device ID: $error');
      return null;
    }
  }

  static Future<bool> clearDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyDeviceId);

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> saveWifiCredentials(String ssid, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySavedSsid, ssid);
      await prefs.setString(_keySavedPassword, password);
      await prefs.setBool(_keyRememberWifi, true);
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> loadWifiCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? ssid = prefs.getString(_keySavedSsid);
      String? password = prefs.getString(_keySavedPassword);
      bool remember = prefs.getBool(_keyRememberWifi) ?? false;

      if (ssid != null && password != null) {
        return {'ssid': ssid, 'password': password, 'remember': remember};
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> saveFanMode(bool isOn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFanMode, isOn);
  }

  static Future<bool> loadFanMode() async {
    final prefs = await SharedPreferences.getInstance();
    final isOn = prefs.getBool(_keyFanMode) ?? false;
    return isOn;
  }

  static Future<void> savePowerState(bool isOn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPowerState, isOn);
  }

  static Future<bool> loadPowerState() async {
    final prefs = await SharedPreferences.getInstance();
    final isOn = prefs.getBool(_keyPowerState) ?? false;

    return isOn;
  }
}
