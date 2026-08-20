/// Unter welcher unserer Adressen wird geantwortet?
///
/// Eigene Datei, weil die Regel klein, wichtig und ohne Bildschirm prüfbar ist.
/// In der ersten Fassung stand sie gar nicht da: die Absenderwahl war gebaut,
/// aber eine Antwort nahm immer das erste Postfach der Liste. Damit ging eine
/// Antwort auf eine Anfrage an `datenschutz@` weiterhin von `icd@` hinaus —
/// also genau der Fehler, den die Funktion beheben sollte, nur mit einem
/// Auswahlfeld darüber.
library;

import 'mail_adressbuch.dart' show mailAdressenAufteilen;
import 'mail_echtheit.dart' show mailAbsenderTeile;

/// Sucht in [empfangenAn] (dem rohen `To`/`Cc` der Ursprungsnachricht) die
/// erste Adresse, unter der dieses Postfach schreiben darf.
///
/// [erlaubte] ist die Liste des Servers, in ihrer Reihenfolge — das eigene
/// Postfach steht dort vorn.
///
/// ⚠️ Die REIHENFOLGE der erlaubten Liste entscheidet, nicht die der Nachricht.
/// Eine Mail an `icd@` **und** `widerruf@` soll unter der allgemeinen Adresse
/// beantwortet werden, nicht unter der, die im Kopf zufällig zuerst steht.
///
/// ⚠️ Verglichen wird auf ganze Adressen, nie mit `contains`. Sonst gälte
/// `nichtwiderruf@icd360s.de` als Treffer für `widerruf@icd360s.de` — und die
/// Antwort ginge unter einer Adresse hinaus, die in der Nachricht nie vorkam.
String? mailAbsenderAusEmpfang(String? empfangenAn, List<String> erlaubte) {
  final roh = (empfangenAn ?? '').trim();
  if (roh.isEmpty) return null;
  // ⚠️ Der `To`-Kopf einer echten Nachricht trägt fast immer Anzeigenamen:
  // `"ICD360S Widerruf" <widerruf@icd360s.de>`. Die blosse Kommatrennung liefert
  // dann das ganze Stück, und der Vergleich geht ins Leere — also genau im
  // Regelfall. Deshalb wird jedes Stück noch von seinem Namen befreit.
  //
  // ⚠️ Ein Anzeigename DARF ein Komma enthalten („Amt, Ulm"). Steht er in
  // Anführungszeichen, zerlegt die Kommatrennung ihn — das Bruchstück ohne
  // spitze Klammern fällt dann einfach nicht auf eine Adresse, und das Stück
  // MIT der Adresse wird weiterhin richtig gelesen.
  final vorhanden = mailAdressenAufteilen(roh)
      .map((a) => mailAbsenderTeile(a).adresse.toLowerCase())
      .where((a) => a.contains('@'))
      .toSet();
  if (vorhanden.isEmpty) return null;
  for (final a in erlaubte) {
    if (vorhanden.contains(a.toLowerCase())) return a;
  }
  return null;
}
