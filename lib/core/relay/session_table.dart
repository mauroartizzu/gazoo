import 'session.dart';

class SessionTable {
  final Map<String, RelaySession> _sessions = {};

  RelaySession? get(String key) => _sessions[key];

  void put(RelaySession session) {
    _sessions[session.key] = session;
  }

  Iterable<RelaySession> get all => _sessions.values;

  int get length => _sessions.length;

  List<RelaySession> sweepExpired(Duration timeout, DateTime now) {
    final expired = _sessions.values.where((s) => s.isExpired(timeout, now)).toList();
    for (final session in expired) {
      session.close();
      _sessions.remove(session.key);
    }
    return expired;
  }

  void removeAndClose(String key) {
    final session = _sessions.remove(key);
    session?.close();
  }

  void closeAll() {
    for (final session in _sessions.values) {
      session.close();
    }
    _sessions.clear();
  }
}
