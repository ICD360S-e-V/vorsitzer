// Das Entpacken des Sprachmodells.
//
// ⚠️ WARUM DAS EIN EIGENER TEST IST: die alte Fassung las das Archiv mit
// `readAsBytes()` und hielt zusätzlich den Inhalt der grössten Datei im
// Speicher. Am echten Modell gemessen (46 MB gepackt, 91,2 MB entpackt, grösste
// Einzeldatei `graph/HCLr.fst` mit 40,0 MB) stieg die Spitze auf 410.708 kB
// gegen 228.792 kB im Strom — 178 MB Unterschied, und das auf einem Tablet, wo
// das der Unterschied zwischen „läuft" und „Speicher voll" ist.
//
// Die Spitze selbst lässt sich hier nicht prüfen; geprüft wird, dass die
// Strom-Fassung dasselbe Ergebnis liefert wie die alte — sonst hätte man
// Speicher gespart und das Modell kaputtgemacht.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/untertitel_modell.dart';

/// Ein Archiv, das aufgebaut ist wie das echte: alles unter EINEM Wurzelordner.
File _archivBauen(Directory tmp, {bool mitBoesemPfad = false}) {
  final a = Archive();
  void datei(String pfad, String inhalt) =>
      a.addFile(ArchiveFile.bytes(pfad, utf8Bytes(inhalt)));

  datei('vosk-model-small-de-0.15/am/final.mdl', 'modell');
  datei('vosk-model-small-de-0.15/conf/model.conf', 'konfiguration');
  datei('vosk-model-small-de-0.15/graph/HCLr.fst', 'graph');
  datei('vosk-model-small-de-0.15/graph/phones/word_boundary.int', 'tief verschachtelt');
  if (mitBoesemPfad) datei('vosk-model-small-de-0.15/../ausbruch.txt', 'darf nicht landen');

  final f = File('${tmp.path}/probe.zip');
  f.writeAsBytesSync(ZipEncoder().encode(a));
  return f;
}

List<int> utf8Bytes(String s) => s.codeUnits;

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('untertitel'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('der Wurzelordner wird weggeschnitten', () {
    // ⚠️ Der ganze Zweck: die native Seite erwartet `am` DIREKT im Ordner.
    // Bliebe die Wurzel stehen, läge dort `vosk-model-small-de-0.15/am` — und
    // `modellDa()` meldete „kein Modell", obwohl 91 MB auf der Platte liegen.
    final zip = _archivBauen(tmp);
    final ziel = Directory('${tmp.path}/ziel')..createSync();

    expect(untertitelArchivEntpacken([zip.path, ziel.path]), isNull);

    expect(File('${ziel.path}/am/final.mdl').existsSync(), isTrue);
    expect(File('${ziel.path}/conf/model.conf').existsSync(), isTrue);
    expect(Directory('${ziel.path}/vosk-model-small-de-0.15').existsSync(), isFalse);
  });

  test('tief verschachtelte Dateien landen vollständig', () {
    final zip = _archivBauen(tmp);
    final ziel = Directory('${tmp.path}/ziel')..createSync();
    untertitelArchivEntpacken([zip.path, ziel.path]);

    final tief = File('${ziel.path}/graph/phones/word_boundary.int');
    expect(tief.existsSync(), isTrue);
    expect(String.fromCharCodes(tief.readAsBytesSync()), 'tief verschachtelt');
  });

  test('ein Eintrag mit .. wird übergangen — auch aus dem eigenen Archiv', () {
    final zip = _archivBauen(tmp, mitBoesemPfad: true);
    final ziel = Directory('${tmp.path}/ziel')..createSync();

    expect(untertitelArchivEntpacken([zip.path, ziel.path]), isNull);
    // Weder neben dem Ziel noch darin.
    expect(File('${tmp.path}/ausbruch.txt').existsSync(), isFalse);
    expect(File('${ziel.path}/ausbruch.txt').existsSync(), isFalse);
    // Und der Rest ist trotzdem da: ein böser Eintrag darf nicht alles kippen.
    expect(File('${ziel.path}/am/final.mdl').existsSync(), isTrue);
  });

  test('ein kaputtes Archiv gibt einen GRUND zurück, statt zu werfen', () {
    // ⚠️ Die Funktion läuft in einem eigenen Isolat. Eine Ausnahme käme beim
    // Aufrufer als `RemoteError` an, in dem von der Ursache wenig übrig ist —
    // und der Vorsitzende sähe eine Meldung, mit der niemand etwas anfangen
    // kann.
    final kaputt = File('${tmp.path}/kaputt.zip')
      ..writeAsBytesSync(List<int>.filled(4096, 7));
    final ziel = Directory('${tmp.path}/ziel')..createSync();

    final grund = untertitelArchivEntpacken([kaputt.path, ziel.path]);
    expect(grund, isNotNull);
    expect(grund, contains('entpacken'));
  });

  test('eine fehlende Datei gibt ebenfalls einen Grund zurück', () {
    final ziel = Directory('${tmp.path}/ziel')..createSync();
    expect(untertitelArchivEntpacken(['${tmp.path}/gibtsnicht.zip', ziel.path]),
        isNotNull);
  });
}
