import 'package:flutter/foundation.dart';

class AppLog extends ChangeNotifier {
  static const int maxLines = 200;

  final List<String> _lines = [];

  List<String> get lines => List.unmodifiable(_lines);

  void append(String message) {
    _lines.add(message);
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
