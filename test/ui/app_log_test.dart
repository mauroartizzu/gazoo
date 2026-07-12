import 'package:flutter_test/flutter_test.dart';
import 'package:gazoo/ui/state/app_log.dart';

void main() {
  test('append adds a line and notifies listeners', () {
    final log = AppLog();
    var notified = 0;
    log.addListener(() => notified++);

    log.append('hello');

    expect(log.lines, ['hello']);
    expect(notified, 1);
  });

  test('append preserves order across multiple calls', () {
    final log = AppLog();
    log.append('first');
    log.append('second');
    expect(log.lines, ['first', 'second']);
  });

  test('caps the buffer at maxLines, dropping the oldest entries first', () {
    final log = AppLog();
    for (var i = 0; i < AppLog.maxLines + 10; i++) {
      log.append('line $i');
    }
    expect(log.lines.length, AppLog.maxLines);
    expect(log.lines.first, 'line 10');
    expect(log.lines.last, 'line ${AppLog.maxLines + 9}');
  });

  test('clear empties the buffer and notifies', () {
    final log = AppLog();
    log.append('hello');
    var notified = 0;
    log.addListener(() => notified++);

    log.clear();

    expect(log.lines, isEmpty);
    expect(notified, 1);
  });
}
