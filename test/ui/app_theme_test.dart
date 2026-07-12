import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gazoo/ui/theme/app_theme.dart';

void main() {
  test('light theme uses Material 3 and light brightness', () {
    final theme = AppTheme.light();
    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.light);
  });

  test('dark theme uses Material 3 and dark brightness', () {
    final theme = AppTheme.dark();
    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.dark);
  });

  test('light and dark themes use distinct color scheme brightness', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    expect(light.colorScheme.brightness, Brightness.light);
    expect(dark.colorScheme.brightness, Brightness.dark);
  });
}
