import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/terminanfrage_versand_dialog.dart';
import 'package:icd360sev_vorsitzer/widgets/terminanfrage_zustellung.dart';

/// Woher der Zustellstand seine Message-ID nimmt.
///
/// 🔴 WARUM DAS EINEN TEST WERT IST
/// „Gesendet" heißt nur, dass UNSER Server die Nachricht übernommen hat. Ob
/// der ZIELSERVER sie angenommen oder mit 554 abgelehnt hat, steht im
/// Postfix-Log — und nachschlagbar ist das ausschließlich über die
/// Message-ID. Die gibt es genau einmal: in der Antwort auf das Senden.
///
/// Verschwindet sie, verschwindet nichts Sichtbares. Die Korrespondenzzeile
/// bleibt stehen und behauptet weiter einen Versand — nur weiß dann für immer
/// niemand mehr, ob er angekommen ist. Genau so war es im ersten Anlauf des
/// Heilmittel-Reiters: die Mail wurde in die Korrespondenz gelegt, die
/// Message-ID aber nicht mitgeschrieben.
///
/// ⚠️ [kMessageIdMarke] steht an ZWEI Stellen — geschrieben beim Ablegen des
/// Arzt-Termins, gelesen von [terminZustellungMessageId]. Ändert jemand nur
/// eine, verschwindet der Zustellstatus lautlos: die Notiz bleibt lesbar, nur
/// findet sie niemand mehr. Dieser Test ist die Stelle, an der das auffällt.
void main() {
  _faxstand();
  group('Message-ID aus den Notizen des Arzt-Termins', () {
    test('wird hinter der Marke gefunden', () {
      final notiz = [
        'Vorlage: Erstvorstellung',
        'Gesendet an: praxis@example.de',
        '${kMessageIdMarke}abc123@icd360s.de',
      ].join('\n');
      expect(terminZustellungMessageId(notiz), 'abc123@icd360s.de');
    });

    test('Reihenfolge der Zeilen ist egal', () {
      final notiz = [
        '${kMessageIdMarke}zuerst@icd360s.de',
        'Gesendet an: praxis@example.de',
      ].join('\n');
      expect(terminZustellungMessageId(notiz), 'zuerst@icd360s.de');
    });

    test('ohne Marke leer — das ist ein Fax oder ein Alteintrag', () {
      expect(terminZustellungMessageId('Gesendet an: 0731 82999'), '');
      expect(terminZustellungMessageId(''), '');
      expect(terminZustellungMessageId(null), '');
    });

    test('sipgate-Sitzung wird NICHT für eine Message-ID gehalten', () {
      // Beides steht in derselben Notiz; nur eines ist im Postfix-Log
      // nachschlagbar. Eine Verwechslung fragte den Mailserver nach einer
      // Faxnummer und bekäme für immer „unbekannt".
      final notiz = [
        'Gesendet an: 0731 82999',
        'sipgate-Sitzung: 4711',
      ].join('\n');
      expect(terminZustellungMessageId(notiz), '');
    });

    test('führende und folgende Leerzeichen fallen weg', () {
      expect(
        terminZustellungMessageId('   $kMessageIdMarke  m@x.de   '),
        'm@x.de',
      );
    });
  });
}

/// ─────────────────────────────────────────────────────────────────────
/// Der Faxstand an der Korrespondenzzeile (seit 30.08.2026).
///
/// Vorher zeigte die Zeile nur bei E-Mail etwas an; ein fehlgeschlagenes Fax
/// sah aus wie ein zugestelltes.
void _faxstand() {
  /// ⚠️ Wörtliche Kopie von `sipgateFaxEndgueltig()` aus
  /// `api/sipgate/sipgate_fax_lib.php`. Das PHP liegt in keinem Repo.
  ///
  /// Wird die Liste dort erweitert, ohne dass es hier ankommt, fragt die App
  /// einen längst fertigen Vorgang bei JEDEM Öffnen der Korrespondenz erneut
  /// bei sipgate nach — ein Fremdaufruf, der nichts mehr ändern kann.
  const serverEndgueltig = {'zugestellt', 'fehlgeschlagen', 'storniert'};

  /// ⚠️ Wörtliche Kopie von `sipgateFaxStatus()` — die Werte, die überhaupt
  /// ankommen können.
  const serverStatus = {
    'zugestellt',
    'fehlgeschlagen',
    'in_zustellung',
    'vorbereitet',
  };

  group('Faxstand', () {
    test('die Endgültig-Liste stimmt mit dem Server überein', () {
      expect(kFaxEndgueltig, serverEndgueltig);
    });

    test('jeder Serverwert hat eine Beschriftung', () {
      // Sonst stünde an der Zeile der rohe Schlüssel — „in_zustellung".
      for (final s in {...serverStatus, ...serverEndgueltig, 'verfallen'}) {
        expect(kFaxStandLabel.containsKey(s), isTrue, reason: 'ohne Text: $s');
      }
    });

    test('„unterwegs" ist NICHT endgültig', () {
      // 🔴 Der Kern des Nachfassens: wäre `in_zustellung` endgültig, bliebe
      // jedes Fax für immer auf „Unterwegs" stehen — und genau die Auskunft,
      // für die die Zeile da ist, käme nie.
      expect(kFaxEndgueltig, isNot(contains('in_zustellung')));
      expect(kFaxEndgueltig, isNot(contains('vorbereitet')));
    });

    test('„vorbereitet" und „in_zustellung" sind unterscheidbar beschriftet', () {
      expect(kFaxStandLabel['vorbereitet'],
          isNot(equals(kFaxStandLabel['in_zustellung'])));
    });
  });
}
