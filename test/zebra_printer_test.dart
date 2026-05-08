import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebrautil/zebra_device.dart';
import 'package:zebrautil/zebra_printer.dart';

const _id = 'test-printer-1';
const _channelName = 'ZebraPrinterObject$_id';
const _channel = MethodChannel(_channelName);

/// Captured method calls and their arguments. Reset in `setUp`.
final List<MethodCall> _calls = [];

/// Stubbed return values per method. Reset in `setUp`.
final Map<String, dynamic> _returns = {};

Future<dynamic> _handler(MethodCall call) async {
  _calls.add(call);
  return _returns[call.method];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _calls.clear();
    _returns.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handler);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('ZebraPrinter.print()', () {
    test('injects ^PON after ^XA when neither rotation marker is present', () {
      final printer = ZebraPrinter(_id);

      printer.print(data: '^XA^FO50,50^FDHello^FS^XZ');

      expect(_calls, hasLength(1));
      expect(_calls.first.method, 'print');
      expect(_calls.first.arguments['Data'],
          '^XA^PON^FO50,50^FDHello^FS^XZ');
    });

    test('rotated → replaces ^PON with ^POI', () {
      final printer = ZebraPrinter(_id);
      printer.rotate();
      expect(printer.isRotated, isTrue);

      printer.print(data: '^XA^FDHi^XZ');

      expect(_calls.first.arguments['Data'], '^XA^POI^FDHi^XZ');
    });

    test('preserves an existing ^PON instead of double-injecting', () {
      final printer = ZebraPrinter(_id);

      printer.print(data: '^XA^PON^FDFoo^XZ');

      // No replaceAll on ^XA → ^XA^PON because ^PON already present.
      expect(_calls.first.arguments['Data'], '^XA^PON^FDFoo^XZ');
    });

    test('rotate() toggles isRotated', () {
      final printer = ZebraPrinter(_id);
      expect(printer.isRotated, isFalse);
      printer.rotate();
      expect(printer.isRotated, isTrue);
      printer.rotate();
      expect(printer.isRotated, isFalse);
    });
  });

  group('ZebraPrinter.connectToPrinter()', () {
    test('returns the bool from the platform on first connect', () async {
      final printer = ZebraPrinter(_id);
      _returns['connectToPrinter'] = true;

      final ok = await printer.connectToPrinter('aa:bb:cc:dd:ee:ff');

      expect(ok, isTrue);
      expect(printer.controller.selectedAddress, 'aa:bb:cc:dd:ee:ff');
      expect(_calls.where((c) => c.method == 'connectToPrinter'),
          hasLength(1));
    });

    test('connecting to the already-selected address disconnects + returns false',
        () async {
      final printer = ZebraPrinter(_id);
      printer.controller.selectedAddress = 'aa:bb:cc:dd:ee:ff';
      _returns['disconnect'] = null;

      final ok = await printer.connectToPrinter('aa:bb:cc:dd:ee:ff');

      expect(ok, isFalse);
      expect(printer.controller.selectedAddress, isNull);
      expect(_calls.where((c) => c.method == 'disconnect'), isNotEmpty);
      expect(_calls.where((c) => c.method == 'connectToPrinter'), isEmpty);
    });

    test('returns false when the platform returns null', () async {
      final printer = ZebraPrinter(_id);
      _returns['connectToPrinter'] = null;

      final ok = await printer.connectToPrinter('aa:bb:cc:dd:ee:ff');

      expect(ok, isFalse);
    });
  });

  group('ZebraPrinter.getCurrentStatus()', () {
    test('parses a known English status', () async {
      final printer = ZebraPrinter(_id);
      _returns['getCurrentStatus'] = 'Connected';

      final status = await printer.getCurrentStatus();

      expect(status, ZebraStatus.connected);
    });

    test('returns unknown when the platform returns null', () async {
      final printer = ZebraPrinter(_id);
      _returns['getCurrentStatus'] = null;

      final status = await printer.getCurrentStatus();

      expect(status, ZebraStatus.unknown);
    });

    test('forwards PlatformException to onDiscoveryError and returns unknown',
        () async {
      String? capturedCode;
      String? capturedText;
      final printer = ZebraPrinter(
        _id,
        onDiscoveryError: (code, text) {
          capturedCode = code;
          capturedText = text;
        },
      );

      // Throw from the channel handler.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'getCurrentStatus') {
          throw PlatformException(code: 'BOOM', message: 'nope');
        }
        return null;
      });

      final status = await printer.getCurrentStatus();

      expect(status, ZebraStatus.unknown);
      expect(capturedCode, 'BOOM');
      expect(capturedText, 'nope');
    });
  });
}
