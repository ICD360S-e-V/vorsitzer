import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die Güte-Messung darf nicht enden, weil EIN Bein aufgelegt hat.
///
/// ⚠️ QUELLTEXT-PRÜFUNG, UND ZWAR ABSICHTLICH — derselbe Aufbau wie in
/// `sipgate_lebenszeichen_test.dart`. Die Regel steht in einer `switch`-Zweig
/// eines privaten Rückrufs, den nur ein laufender SIP-Stack mit ZWEI
/// verbundenen Beinen auslöst. Um sie beobachtend zu prüfen, müsste man den
/// halben Stack nachbilden und am Ende dieselbe Eigenschaft prüfen, die hier
/// direkt dasteht.
///
/// Der Fehler, den das verhindert, wäre still gewesen: legt in einer Konferenz
/// einer der beiden auf, liefe das andere Gespräch weiter — aber der Bildschirm
/// zeigte bis zum Schluss „wird gemessen …", und im Protokoll stünde nichts.
/// Genau die Klasse Fehler, vor der der Kommentar beim Abräumen der Beine
/// warnt: „es zu beenden, weil ein Ereignis für das andere Bein kam, wäre der
/// schlimmste Fehler hier."
void main() {
  late String quelle;

  setUpAll(() {
    final f = File('lib/services/sipgate_service.dart');
    expect(f.existsSync(), isTrue);
    quelle = f.readAsStringSync();
  });

  test('das Gesprächsende fragt, ob noch ein Bein übrig ist', () {
    expect(quelle, contains("final letztesBein = (seite == 'A' ? _rufB : _rufA) == null;"));
  });

  test('die Bilanz wird NUR beim letzten Bein geschrieben', () {
    // Sonst trüge das eine Gespräch die Aussetzer des anderen — und zwar
    // unauffällig, weil die Zahl ja plausibel aussähe.
    expect(quelle, contains('letztesBein ? gueteBilanz.alsKarte() : null'));
  });

  test('bleibt ein Bein, wird frisch begonnen statt weitergezählt', () {
    final i = quelle.indexOf('final letztesBein');
    expect(i, isNot(-1));
    final ausschnitt = quelle.substring(i, i + 400);
    expect(ausschnitt, contains('if (letztesBein) {'));
    expect(ausschnitt, contains('_gueteStoppen();'));
    expect(ausschnitt, contains('_gueteStarten();'));
  });

  test('_gueteStarten setzt Sonde UND Bilanz zurück', () {
    // ⚠️ Ohne beides wäre der erste Takt des nächsten Gesprächs die Differenz
    // zum vorigen — Unsinn, der plausibel aussieht.
    final i = quelle.indexOf('void _gueteStarten()');
    expect(i, isNot(-1));
    final rumpf = quelle.substring(i, quelle.indexOf('void _gueteStoppen()'));
    expect(rumpf, contains('_sonde.zuruecksetzen();'));
    expect(rumpf, contains('gueteBilanz.leeren();'));
    expect(rumpf, contains('guete.value = null;'));
  });

  test('ein Fehler beim Messen bricht den Takt NICHT ab', () {
    // Die Güte ist Beiwerk; ein Gespräch darf nie daran scheitern, dass eine
    // Kennzahl nicht zu holen war.
    final i = quelle.indexOf('Future<void> _gueteAbfragen()');
    expect(i, isNot(-1));
    final rumpf = quelle.substring(i, i + 900);
    expect(rumpf, contains('} catch (e) {'));
    expect(rumpf, isNot(contains('_gueteTakt?.cancel()')));
    // Einmal melden, nicht bei jedem Takt.
    expect(rumpf, contains('_gueteGemeldet'));
  });
}
