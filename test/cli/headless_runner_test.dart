import 'package:test/test.dart';
import 'package:gazoo/cli/headless_runner.dart';

void main() {
  test('returns null when --headless is not present', () {
    expect(parseHeadlessArgs(['--server=example.com:19132']), isNull);
    expect(parseHeadlessArgs([]), isNull);
  });

  test('parses host and port from --server', () {
    final args = parseHeadlessArgs(['--headless', '--server=example.com:19132']);
    expect(args, isNotNull);
    expect(args!.host, 'example.com');
    expect(args.port, 19132);
  });

  test('applies default name and proxy port when not specified', () {
    final args = parseHeadlessArgs(['--headless', '--server=example.com:19132']);
    expect(args!.name, 'Gazoo Server');
    expect(args.proxyPort, 19133);
  });

  test('parses --name and --proxy-port overrides', () {
    final args = parseHeadlessArgs([
      '--headless',
      '--server=example.com:19132',
      '--name=My Server',
      '--proxy-port=19140',
    ]);
    expect(args!.name, 'My Server');
    expect(args.proxyPort, 19140);
  });

  test('throws HeadlessArgsError when --server is missing', () {
    expect(
      () => parseHeadlessArgs(['--headless']),
      throwsA(isA<HeadlessArgsError>()),
    );
  });

  test('throws HeadlessArgsError when --server is malformed (no colon)', () {
    expect(
      () => parseHeadlessArgs(['--headless', '--server=example.com']),
      throwsA(isA<HeadlessArgsError>()),
    );
  });

  test('throws HeadlessArgsError when the port is not numeric', () {
    expect(
      () => parseHeadlessArgs(['--headless', '--server=example.com:notaport']),
      throwsA(isA<HeadlessArgsError>()),
    );
  });

  test('throws HeadlessArgsError when the port is 0', () {
    expect(
      () => parseHeadlessArgs(['--headless', '--server=example.com:0']),
      throwsA(isA<HeadlessArgsError>()),
    );
  });

  test('throws HeadlessArgsError when the port is out of range (99999)', () {
    expect(
      () => parseHeadlessArgs(['--headless', '--server=example.com:99999']),
      throwsA(isA<HeadlessArgsError>()),
    );
  });

  test('throws HeadlessArgsError when --proxy-port is 19132 (reserved for discovery)', () {
    expect(
      () => parseHeadlessArgs([
        '--headless',
        '--server=example.com:19132',
        '--proxy-port=19132',
      ]),
      throwsA(isA<HeadlessArgsError>()),
    );
  });

  test('ignores unrelated arguments', () {
    final args = parseHeadlessArgs(['--some-other-flag', '--headless', '--server=example.com:19132']);
    expect(args, isNotNull);
    expect(args!.host, 'example.com');
  });
}
