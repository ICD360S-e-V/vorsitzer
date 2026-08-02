import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/file_picker_helper.dart';

/// Hintergrund: `saveBytes` darf dem Plugin keinen Dateinamen ohne Endung
/// geben. Unter Android hängt `file_picker` sonst selbst eine an, die es aus
/// dem Inhalt errät — und tut das seit 11.0.3 über
/// `URLConnection.guessContentTypeFromStream` statt über Apache Tika. Für PDF
/// und ZIP liefert das `null`, woraufhin aus einem Bescheid `dokument.octet-stream`
/// wird statt `dokument.pdf`.
///
/// Diese Tests decken deshalb genau die Formate ab, die dabei durchfallen
/// würden, plus die, die weiterhin erkannt werden.
Uint8List _bytes(List<int> head, {int pad = 32}) =>
    Uint8List.fromList([...head, ...List<int>.filled(pad, 0)]);

void main() {
  group('extensionFromMagicBytes', () {
    test('erkennt PDF — der Fall, an dem der Plugin-Rateweg scheitert', () {
      // "%PDF-1.4"
      final pdf = _bytes([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]);
      expect(FilePickerHelper.extensionFromMagicBytes(pdf), 'pdf');
    });

    test('erkennt ZIP, das der Plugin-Rateweg ebenfalls nicht erkennt', () {
      final zip = _bytes([0x50, 0x4B, 0x03, 0x04]);
      expect(FilePickerHelper.extensionFromMagicBytes(zip), 'zip');
    });

    test('erkennt die Bildformate der Behörden-Anhänge', () {
      expect(
        FilePickerHelper.extensionFromMagicBytes(
          _bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ),
        'png',
      );
      expect(
        FilePickerHelper.extensionFromMagicBytes(_bytes([0xFF, 0xD8, 0xFF, 0xE0])),
        'jpg',
      );
      expect(
        FilePickerHelper.extensionFromMagicBytes(_bytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])),
        'gif',
      );
    });

    test('erkennt TIFF in beiden Byte-Reihenfolgen', () {
      expect(
        FilePickerHelper.extensionFromMagicBytes(_bytes([0x49, 0x49, 0x2A, 0x00])),
        'tif',
      );
      expect(
        FilePickerHelper.extensionFromMagicBytes(_bytes([0x4D, 0x4D, 0x00, 0x2A])),
        'tif',
      );
    });

    test('erkennt HEIC, dessen Kennung erst ab Byte 4 steht', () {
      // 4 Byte Box-Länge, dann "ftyp", dann "heic"
      final heic = _bytes([
        0x00, 0x00, 0x00, 0x18, //
        0x66, 0x74, 0x79, 0x70, // ftyp
        0x68, 0x65, 0x69, 0x63, // heic
      ]);
      expect(FilePickerHelper.extensionFromMagicBytes(heic), 'heic');
    });

    test('hält ein blosses "ftyp" ohne HEIC-Marke nicht für HEIC', () {
      // ftyp + "mp42" ist ein Video, keine Bilddatei.
      final mp4 = _bytes([
        0x00, 0x00, 0x00, 0x18, //
        0x66, 0x74, 0x79, 0x70, // ftyp
        0x6D, 0x70, 0x34, 0x32, // mp42
      ]);
      expect(FilePickerHelper.extensionFromMagicBytes(mp4), isNull);
    });

    test('erkennt XML', () {
      final xml = _bytes([0x3C, 0x3F, 0x78, 0x6D, 0x6C]); // <?xml
      expect(FilePickerHelper.extensionFromMagicBytes(xml), 'xml');
    });

    test('gibt null zurueck, wenn nichts passt — der Name bleibt dann unveraendert', () {
      expect(
        FilePickerHelper.extensionFromMagicBytes(_bytes([0x01, 0x02, 0x03, 0x04])),
        isNull,
      );
    });

    test('kommt mit zu kurzen und leeren Daten klar, statt zu werfen', () {
      expect(FilePickerHelper.extensionFromMagicBytes(Uint8List(0)), isNull);
      // Ein PDF-Anfang, der mitten in der Signatur endet.
      expect(
        FilePickerHelper.extensionFromMagicBytes(Uint8List.fromList([0x25, 0x50])),
        isNull,
      );
      // Genau lang genug fuer "ftyp", aber zu kurz fuer die Marke dahinter.
      expect(
        FilePickerHelper.extensionFromMagicBytes(
          Uint8List.fromList([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70]),
        ),
        isNull,
      );
    });
  });
}
