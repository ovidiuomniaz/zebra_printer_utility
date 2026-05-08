import 'package:flutter_test/flutter_test.dart';
import 'package:zebrautil/zebra_device.dart';

void main() {
  group('zebraStatusFromStrings', () {
    group('English keywords', () {
      test('"Connected" → connected', () {
        expect(zebraStatusFromStrings('Connected'), ZebraStatus.connected);
      });
      test('"Disconnected" → disconnected', () {
        expect(zebraStatusFromStrings('Disconnected'), ZebraStatus.disconnected);
      });
      test('"Connecting…" → connecting', () {
        expect(zebraStatusFromStrings('Connecting…'), ZebraStatus.connecting);
      });
      test('"Disconnecting" → disconnecting', () {
        expect(zebraStatusFromStrings('Disconnecting'), ZebraStatus.disconnecting);
      });
      test('"Sending Data" → sendingData', () {
        expect(zebraStatusFromStrings('Sending Data'), ZebraStatus.sendingData);
      });
      test('"Done" → done', () {
        expect(zebraStatusFromStrings('Done'), ZebraStatus.done);
      });
      test('"Port Invalid" → portInvalid', () {
        expect(zebraStatusFromStrings('Port Invalid'), ZebraStatus.portInvalid);
      });
      test('"Ready To Print" → connected (treated as ready)', () {
        expect(zebraStatusFromStrings('Ready To Print'), ZebraStatus.connected);
      });
      test('"Cannot Print: Paper Out" → disconnected (generic error)', () {
        expect(zebraStatusFromStrings('Cannot Print: Paper Out'),
            ZebraStatus.disconnected);
      });
    });

    group('Spanish keywords', () {
      test('"Conectado" → connected', () {
        expect(zebraStatusFromStrings('Conectado'), ZebraStatus.connected);
      });
      test('"Desconectado" → disconnected', () {
        expect(zebraStatusFromStrings('Desconectado'), ZebraStatus.disconnected);
      });
      test('"Conectando" → connecting', () {
        expect(zebraStatusFromStrings('Conectando'), ZebraStatus.connecting);
      });
      test('"Desconectando" → disconnecting', () {
        expect(
            zebraStatusFromStrings('Desconectando'), ZebraStatus.disconnecting);
      });
      test('"Enviando información" → sendingData', () {
        expect(zebraStatusFromStrings('Enviando información'),
            ZebraStatus.sendingData);
      });
      test('"Completado" → done', () {
        expect(zebraStatusFromStrings('Completado'), ZebraStatus.done);
      });
    });

    group('case insensitivity & trimming', () {
      test('"connected" lowercase → connected', () {
        expect(zebraStatusFromStrings('connected'), ZebraStatus.connected);
      });
      test('"  CONNECTED  " trims and lowers', () {
        expect(zebraStatusFromStrings('  CONNECTED  '), ZebraStatus.connected);
      });
      test('mixed case "ConNected" → connected', () {
        expect(zebraStatusFromStrings('ConNected'), ZebraStatus.connected);
      });
    });

    group('color fallback when label is unknown', () {
      test('color G → connected', () {
        expect(zebraStatusFromStrings('foo', color: 'G'), ZebraStatus.connected);
      });
      test('color R → disconnected', () {
        expect(
            zebraStatusFromStrings('foo', color: 'R'), ZebraStatus.disconnected);
      });
      test('color Y → connecting', () {
        expect(zebraStatusFromStrings('foo', color: 'Y'), ZebraStatus.connecting);
      });
      test('lowercase color g still resolves', () {
        expect(zebraStatusFromStrings('foo', color: 'g'), ZebraStatus.connected);
      });
      test('label wins over color when label is recognized', () {
        // English "Disconnected" + color G → disconnected (label wins)
        expect(zebraStatusFromStrings('Disconnected', color: 'G'),
            ZebraStatus.disconnected);
      });
    });

    group('isConnected fallback', () {
      test('unknown label, no color, isConnected:true → connected', () {
        expect(zebraStatusFromStrings('xyz', isConnected: true),
            ZebraStatus.connected);
      });
      test('unknown label, no color, isConnected:false → unknown', () {
        expect(zebraStatusFromStrings('xyz', isConnected: false),
            ZebraStatus.unknown);
      });
    });

    group('null and empty', () {
      test('null → unknown', () {
        expect(zebraStatusFromStrings(null), ZebraStatus.unknown);
      });
      test('"" → unknown', () {
        expect(zebraStatusFromStrings(''), ZebraStatus.unknown);
      });
      test('whitespace only → unknown', () {
        expect(zebraStatusFromStrings('   '), ZebraStatus.unknown);
      });
    });
  });
}
