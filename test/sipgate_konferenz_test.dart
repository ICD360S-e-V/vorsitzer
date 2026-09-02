import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die Dreierkonferenz — und warum sie vorher nicht funktionieren KONNTE.
///
/// 🔴 sipgate schreibt die Reihenfolge selbst vor (help.sipgate.de,
/// „Tastenkürzel bei sipgate"):
///
///     Halten      *3
///     Transfer    *3<Rufnummer>#
///     Konferenz   *5  — „nach dem Transfer eines weiteren Teilnehmers"
///
/// Die alte Fassung hielt mit `*3` und öffnete dann einen ZWEITEN,
/// eigenständigen SIP-Dialog. Für die Anlage waren das zwei Anrufe ohne
/// Zusammenhang; ein späteres `*5` hatte nichts zusammenzuschalten. Nichts
/// schlug dabei fehl — der Knopf erschien nur nie, weil seine Bedingung an
/// einem Zustand hing, den es nicht mehr gab.
///
/// Geprüft wird der Quelltext, weil dieser Zweig einen laufenden SIP-Stack
/// und zwei abgehobene Gegenstellen braucht.
void main() {
  final dienst = File('lib/services/sipgate_service.dart').readAsStringSync();
  final overlay =
      File('lib/widgets/sipgate_anruf_overlay.dart').readAsStringSync();

  /// Schneidet den Bereich zwischen zwei Ankern aus.
  ///
  /// ⚠️ Wirft, statt `expect` zu benutzen: die Aufrufe stehen im Rumpf von
  /// `group`, und der läuft beim EINLESEN der Datei, nicht in einem Test. Ein
  /// `expect` dort scheitert mit `OutsideTestException` — die ganze Datei
  /// lädt dann nicht, und man sucht den Fehler in den Zusicherungen statt im
  /// Anker.
  ///
  /// ⚠️ Und die Anker sind Deklarationen, keine Zeichenzahl: ein Fenster
  /// „ab hier N Zeichen" zerbricht, sobald jemand einen Kommentar ergänzt.
  String rumpf(String quelle, String beginn, String ende) {
    final i = quelle.indexOf(beginn);
    if (i < 0) throw StateError('Anker „$beginn" nicht gefunden');
    final j = quelle.indexOf(ende, i + beginn.length);
    if (j <= i) throw StateError('Ende „$ende" nicht gefunden');
    return quelle.substring(i, j);
  }

  group('die zweite Nummer geht über die Anlage', () {
    final r = rumpf(dienst, 'Future<String?> _zweitesWaehlen(',
        'Future<bool> _steuerfolge(');

    test('gewählt wird mit *3 … # auf dem laufenden Gespräch', () {
      expect(r, contains("_steuerfolge(ruf, ['*3', nummer, '#'])"));
    });

    test('KEIN zweiter SIP-Ruf mehr', () {
      // 🔴 Das ist die eigentliche Zusicherung. `_helper.call(...)` hier wäre
      // der Rückfall in genau den Fehler: zwei Dialoge, die die Anlage nicht
      // zusammenbringen kann.
      expect(r.contains('_helper.call'), isFalse,
          reason: 'Der zweite Teilnehmer wird wieder als eigener SIP-Ruf '
              'gewählt — dann kann *5 ihn nicht dazuschalten');
    });

    test('das erste Bein wird dabei gehalten', () {
      // Sonst hört die erste Person zu, während man die zweite wählt — bei
      // einem Amt und einem Mitglied im selben Gespräch genau das, was nicht
      // passieren darf.
      expect(r, contains("_setzBein('A', (g) => g.kopie(gehalten: true))"));
    });

    test('der zweite Teilnehmer gilt als „wählt", nicht als „verbunden"', () {
      // ⚠️ Für ihn gibt es keinen eigenen SIP-Dialog, also auch kein Signal,
      // wenn er abhebt. „verbunden" wäre eine Angabe, die niemand geprüft hat.
      expect(r, contains('stand: SipgateGespraechStand.waehlt'));
      expect(r.contains('stand: SipgateGespraechStand.verbunden'), isFalse);
    });
  });

  group('die Ziffern gehen einzeln hinaus', () {
    final r = rumpf(dienst, 'Future<bool> _steuerfolge(', '  bool _steuercode(');

    test('mit Pause zwischen den Tönen', () {
      // ⚠️ Eine Anlage erkennt eine Folge über die Lücken. Kommt alles in einem
      // Block, verschmelzen Wiederholungen oder es wird gar nicht als Wahl
      // erkannt.
      expect(r, contains('Duration(milliseconds:'));
      expect(r, contains('await Future<void>.delayed'));
    });

    test('was keine Taste ist, kommt nicht auf die Leitung', () {
      // Ein „+" oder ein Leerzeichen aus einer Rufnummer würde die Folge
      // zerreissen.
      expect(r, contains("'0123456789*#'.contains(zeichen)"));
    });
  });

  group('wann der Konferenzknopf erscheint', () {
    final r = rumpf(dienst, 'bool get kannKonferenz', 'Ob auf DIESEM Gerät');

    test('nicht mehr an zwei verbundenen SIP-Beinen', () {
      // 🔴 Der zweite Grund, warum der Knopf nie kam: seit der Teilnehmer über
      // die Anlage dazukommt, gibt es für ihn kein `verbunden` — die Bedingung
      // konnte nicht mehr wahr werden, und nichts schlug dabei fehl.
      expect(r.contains('verbundeneBeine'), isFalse,
          reason: 'kannKonferenz hängt wieder an einem Zustand, den der über '
              'die Anlage gewählte Teilnehmer nie erreicht');
    });

    test('sondern daran, dass überhaupt ein zweiter dazugewählt ist', () {
      expect(r, contains('zustand.value.zweites != null'));
    });
  });

  group('erreichbar von der schwebenden Karte', () {
    test('es gibt einen Knopf für die Gesprächsfunktionen', () {
      // 🔴 Gemeldet als „der Konferenzknopf ist weg". Er war nie weg — er stand
      // nur im Vollbild, und wer telefoniert, sieht diese Karte.
      expect(overlay, contains('_funktionen(context, dienst, z)'));
      expect(overlay, contains('Icons.more_horiz'));
    });

    test('Konferenz und Wechseln stehen im Menü', () {
      final r = rumpf(overlay, 'void _funktionen(', 'Widget _rundKnopf(');
      // ⚠️ Der Menüpunkt schickt NICHT mehr selbst `*5`, sondern öffnet den
      // Ablauf: von dort führt ein Weg zur zweiten Nummer, und der Hinweis
      // „erst wenn abgehoben" steht dabei. Ein Knopf, der sofort schaltet,
      // liesse den zweiten Schritt wieder weg.
      expect(r, contains('konferenzAblauf(context)'));
      expect(r, contains('dienst.makeln()'));
    });

    test('am Konferenzknopf steht, wann er zu drücken ist', () {
      // ⚠️ Ohne den Satz drückt man zu früh und schaltet ins Leere — für den
      // zweiten Teilnehmer gibt es kein Abheben-Signal.
      final r = rumpf(overlay, 'void _funktionen(', 'Widget _rundKnopf(');
      expect(r, contains('abgehoben hat'));
    });
  });
}
