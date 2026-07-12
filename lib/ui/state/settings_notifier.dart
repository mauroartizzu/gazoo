import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/settings.dart';

class SettingsNotifier extends ChangeNotifier {
  static const _prefsKey = 'settings';

  final SharedPreferences prefs;
  Settings _settings = Settings.defaults;

  SettingsNotifier({required this.prefs}) {
    _loadFromPrefs();
  }

  Settings get settings => _settings;

  void _loadFromPrefs() {
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    _settings = Settings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _persist() async {
    await prefs.setString(_prefsKey, jsonEncode(_settings.toJson()));
  }

  Future<void> update(Settings Function(Settings current) updater) async {
    _settings = updater(_settings);
    notifyListeners();
    await _persist();
  }
}
