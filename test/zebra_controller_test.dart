import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebrautil/zebra_device.dart';
import 'package:zebrautil/zebra_printer.dart';

ZebraDevice _device(String address,
        {String name = 'Printer', bool isConnected = false}) =>
    ZebraDevice(
      address: address,
      name: name,
      isWifi: false,
      status: isConnected ? 'Connected' : 'Disconnected',
      statusEnum:
          isConnected ? ZebraStatus.connected : ZebraStatus.disconnected,
      isConnected: isConnected,
    );

void main() {
  group('ZebraController', () {
    late ZebraController controller;

    setUp(() {
      controller = ZebraController();
    });

    test('starts empty', () {
      expect(controller.printers, isEmpty);
      expect(controller.selectedAddress, isNull);
    });

    group('addPrinter', () {
      test('adds a new printer and notifies', () {
        var notified = 0;
        controller.addListener(() => notified++);

        controller.addPrinter(_device('00:11:22:33:44:55'));

        expect(controller.printers, hasLength(1));
        expect(controller.printers.first.address, '00:11:22:33:44:55');
        expect(notified, 1);
      });

      test('deduplicates by address (no notify on duplicate)', () {
        controller.addPrinter(_device('aa:bb:cc:dd:ee:ff', name: 'First'));
        var notified = 0;
        controller.addListener(() => notified++);

        controller.addPrinter(_device('aa:bb:cc:dd:ee:ff', name: 'Second'));

        expect(controller.printers, hasLength(1));
        expect(controller.printers.first.name, 'First',
            reason: 'first wins; second add is a no-op');
        expect(notified, 0);
      });

      test('returns an unmodifiable view', () {
        controller.addPrinter(_device('aa'));
        expect(() => controller.printers.add(_device('bb')),
            throwsUnsupportedError);
      });
    });

    group('removePrinter', () {
      test('removes by address', () {
        controller.addPrinter(_device('aa'));
        controller.addPrinter(_device('bb'));
        controller.removePrinter('aa');

        expect(controller.printers, hasLength(1));
        expect(controller.printers.first.address, 'bb');
      });

      test('removing missing address is a no-op', () {
        controller.addPrinter(_device('aa'));
        controller.removePrinter('does-not-exist');
        expect(controller.printers, hasLength(1));
      });
    });

    group('cleanAll', () {
      test('keeps connected printers, drops disconnected ones', () {
        controller.addPrinter(_device('aa', isConnected: true));
        controller.addPrinter(_device('bb', isConnected: false));
        controller.addPrinter(_device('cc', isConnected: false));

        controller.cleanAll();

        expect(controller.printers, hasLength(1));
        expect(controller.printers.first.address, 'aa');
      });

      test('on empty list is a no-op', () {
        controller.cleanAll();
        expect(controller.printers, isEmpty);
      });
    });

    group('updatePrinterStatus', () {
      test('updates the selected printer with correct color and status', () {
        controller.addPrinter(_device('aa'));
        controller.selectedAddress = 'aa';

        controller.updatePrinterStatus('Connected', 'G');

        final updated = controller.printers.first;
        expect(updated.isConnected, isTrue);
        expect(updated.statusEnum, ZebraStatus.connected);
        expect(updated.color, Colors.green);
        expect(updated.status, 'Connected');
      });

      test('color R maps to red', () {
        controller.addPrinter(_device('aa'));
        controller.selectedAddress = 'aa';

        controller.updatePrinterStatus('Disconnected', 'R');

        expect(controller.printers.first.color, Colors.red);
      });

      test('does nothing when no address is selected', () {
        controller.addPrinter(_device('aa'));
        // selectedAddress stays null

        // Should not throw; should not update.
        controller.updatePrinterStatus('Connected', 'G');

        expect(controller.printers.first.isConnected, isFalse);
      });
    });

    group('synchronizePrinter', () {
      test('marks the selected printer connected', () {
        controller.addPrinter(_device('aa'));
        controller.selectedAddress = 'aa';

        controller.synchronizePrinter('Connected');

        expect(controller.printers.first.isConnected, isTrue);
        expect(controller.printers.first.statusEnum, ZebraStatus.connected);
      });

      test('clears selectedAddress when no matching printer', () {
        controller.selectedAddress = 'ghost';
        controller.synchronizePrinter('Connected');
        expect(controller.selectedAddress, isNull);
      });

      test('is a no-op when the printer is already connected', () {
        controller.addPrinter(_device('aa', isConnected: true));
        controller.selectedAddress = 'aa';
        var notified = 0;
        controller.addListener(() => notified++);

        controller.synchronizePrinter('Already there');

        expect(notified, 0);
        expect(controller.printers.first.status, 'Connected',
            reason: 'unchanged');
      });

      test('does nothing when no address is selected', () {
        controller.addPrinter(_device('aa'));
        controller.synchronizePrinter('Connected');
        expect(controller.printers.first.isConnected, isFalse);
      });
    });
  });
}
