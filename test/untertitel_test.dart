import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/untertitel_service.dart';

/// Live-Mitschrift dessen, was die Gegenstelle sagt.
///
/// ⚠️ DIE WICHTIGSTE EIGENSCHAFT IST EINE, DIE MAN NICHT SIEHT: es wird nichts
/// aufgezeichnet und nichts gespeichert. Festlegung des Users, und zugleich die
/// Linie des § 201 StGB — mitlesen, um zu verstehen, ist etwas anderes als eine
/// Aufnahme des gesprochenen Wortes. Diese Tests halten fest, dass es dabei
/// bleibt.
void main() {
  /// Nur der Code — ohne Zeilen- UND ohne Blockkommentare.
  ///
  /// ⚠️ Die Blockkommentare gehören dazu, und das hat dieser Test auf die
  /// harte Tour gelernt: die Begründung im KDoc von `Untertitel.kt` nennt
  /// `SpeechRecognizer` und `EXTRA_AUDIO_SOURCE` genau deshalb, WEIL sie nicht
  /// benutzt werden. Ein Test, der nur `//` wegwirft, scheitert dann an der
  /// eigenen Erklärung — schon zum zweiten Mal in diesem Projekt (siehe
  /// `sipgate_weiterverbinden_test.dart`).
  List<String> nurCode(String q) => q
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') &&
            !t.startsWith('/*') &&
            !t.startsWith('*');
      })
      .toList();
  String code(String p) => nurCode(File(p).readAsStringSync()).join('\n');

  group('nichts wird gespeichert', () {
    test('der Dienst schreibt in keine Datei und in keine Ablage', () {
      final q = code('lib/services/untertitel_service.dart');
      for (final verboten in const [
        'SharedPreferences', 'SecureStore', 'sipgateAction',
        'writeAsString', 'insert(',
      ]) {
        expect(q, isNot(contains(verboten)),
            reason: 'die Mitschrift darf $verboten nicht anfassen');
      }
    });

    test('beenden() räumt den Text weg', () async {
      final u = UntertitelService();
      u.text.value = 'etwas, das dastand';
      await u.beenden();
      expect(u.text.value, isEmpty);
      expect(u.aktiv.value, isFalse);
    });

    test('das Gesprächsende beendet die Mitschrift', () {
      // Sonst bliebe der letzte Satz stehen, nachdem aufgelegt wurde — und
      // wäre damit faktisch doch aufbewahrt.
      final q = code('lib/services/sipgate_service.dart');
      expect(q, contains('UntertitelService().beenden()'));
    });
  });

  group('kein Google im Weg — und das ist Notwendigkeit, nicht Haltung', () {
    // Androids Offline-Erkenner ist Googles „Android System Intelligence", ein
    // Teil von Play. Ohne Play gibt es ihn nicht: auf GrapheneOS meldet
    // `isOnDeviceRecognitionAvailable()` false, und im Fehlerverfolger des
    // Projekts steht so ein Dienst als OFFENE Bitte (#1593). Auf dem künftigen
    // Pixel Fold wäre die Mitschrift also nie angesprungen — dieselbe Fassung
    // läuft nun auf dem heutigen Samsung A11 und auf dem Pixel.
    const k = 'android/app/src/main/kotlin/de/icd360sev/vorsitzer/Untertitel.kt';

    test('Androids Erkenner wird gar nicht erst angefasst', () {
      final q = code(k);
      for (final verboten in const [
        'SpeechRecognizer',
        'RecognizerIntent',
        'EXTRA_AUDIO_SOURCE',
        'com.google.android',
      ]) {
        expect(q, isNot(contains(verboten)), reason: 'noch vorhanden: $verboten');
      }
    });

    test('erkannt wird mit Vosk, auf dem Gerät', () {
      final q = code(k);
      expect(q, contains('org.vosk.Recognizer'));
      expect(q, contains('acceptWaveForm'));
    });

    test('das Mikrofon kommt im ganzen Weg nicht vor', () {
      // ⚠️ DAS IST DER PUNKT, DEN DIE ALTE FASSUNG NOCH PRÜFEN MUSSTE.
      // Androids Erkenner öffnet laut eigener Doku stillschweigend das
      // Mikrofon, wenn er die mitgegebene Tonquelle nicht unterstützt — er
      // schriebe dann den Raum mit statt das Gespräch, und sähe dabei aus, als
      // ginge alles. Dafür gab es hier eine eigene Probe. Mit Vosk gehen die
      // Proben aus dem `AudioTrackSink` unmittelbar in den Erkenner; der
      // Fehler kann nicht mehr auftreten, und die Probe ist deshalb weg.
      final q = code(k);
      expect(q, contains('AudioTrackSink'));
      for (final verboten in const ['AudioRecord', 'MediaRecorder', 'AudioSource']) {
        expect(q, isNot(contains(verboten)), reason: 'noch vorhanden: $verboten');
      }
    });
  });

  group('das Sprachmodell', () {
    const m = 'lib/services/untertitel_modell.dart';

    test('erst prüfen, dann entpacken', () {
      // Ein abgerissener Download ergäbe ein halbes Modell — Vosk lädt es dann
      // entweder gar nicht oder, schlimmer, mit fehlenden Teilen.
      //
      // ⚠️ GEMESSEN WIRD INNERHALB VON `holen()`, nicht über die ganze Datei.
      // Die erste Fassung verglich die Stellen von `sha256` und `ZipDecoder`
      // im gesamten Quelltext. Das hielt genau so lange, wie beides in
      // derselben Methode stand: als das Entpacken am 30.08.2026 in eine
      // Funktion auf Dateiebene wanderte (eigenes Isolat, siehe
      // `untertitelArchivEntpacken`), stand `ZipDecoder` plötzlich WEITER OBEN
      // als die Prüfsumme — und der Test schlug fehl, obwohl sich an der
      // Reihenfolge zur Laufzeit nichts geändert hatte.
      //
      // Eine Prüfung über Zeichenpositionen misst die Anordnung im Text; hier
      // gemeint ist die Reihenfolge im Ablauf. Deshalb wird jetzt der Rumpf
      // von `holen()` ausgeschnitten und darin verglichen.
      final q = code(m);
      expect(q, contains('sha256'));

      final start = q.indexOf('Future<String?> holen(');
      expect(start, isNot(-1), reason: 'holen() nicht gefunden');
      final rumpf = q.substring(start);

      final pruefung = rumpf.indexOf('sha256');
      final entpacken = rumpf.indexOf('untertitelArchivEntpacken');
      expect(pruefung, isNot(-1), reason: 'keine Prüfsumme in holen()');
      expect(entpacken, isNot(-1), reason: 'kein Entpacken in holen()');
      expect(pruefung, lessThan(entpacken),
          reason: 'die Prüfsumme muss VOR dem Entpacken drankommen');
    });

    test('daneben entpacken, dann umbenennen', () {
      // Bricht das Entpacken ab, stünde sonst ein halbes Modell genau dort, wo
      // die native Seite ein ganzes erwartet.
      final q = code(m);
      expect(q, contains(".neu'"));
      expect(q, contains('rename('));
    });

    test('kein Pfaddurchstieg aus dem Archiv', () {
      expect(code(m), contains("contains('..')"));
    });

    test('der Ordner passt zu dem, den die native Seite sucht', () {
      // `getApplicationSupportDirectory()` IST `filesDir` (nachgesehen in
      // path_provider_android). Laufen die beiden Namen auseinander, holt die
      // App ein Modell, das die native Seite nie findet.
      expect(code(m), contains("/vosk-de'"));
      expect(
          code('android/app/src/main/kotlin/de/icd360sev/vorsitzer/Untertitel.kt'),
          contains('"vosk-de"'));
    });
  });

  group('Ränder', () {
    test('ohne Tonspur wird nicht gestartet', () async {
      final grund = await UntertitelService().starten('');
      expect(grund, isNotNull);
      expect(UntertitelService().aktiv.value, isFalse);
    });
  });
}
