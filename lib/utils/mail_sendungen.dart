/// Aufteilung von Anhängen auf mehrere E-Mails.
///
/// WARUM ES DAS GIBT
/// -----------------
/// Eine Mail trägt bei uns 20 Anhänge und 25 MB. Die erste Grenze ist keine
/// Höflichkeit, sondern PHPs `max_file_uploads`: **darüber verwirft der
/// Server den Rest STILL**. Ein Abschnitt der Insolvenz-Unterlagen hat aber
/// ohne Weiteres 25 eingescannte Seiten — gemessen an einer echten Akte.
///
/// Wer in so einem Fall einfach 25 Anhänge übergibt, verschickt 20 und hält
/// die Sendung für vollständig. Deshalb wird hier vorher geteilt, und der
/// Brief jeder Teilsendung sagt „Teil 1 von 2".
///
/// ⚠️ Was **einzeln** schon zu groß ist, landet nicht in einer Sendung,
/// sondern in `zuGross`. Es stillschweigend wegzulassen wäre der schlimmste
/// Ausgang: das Anschreiben zählt die Anlagen namentlich auf, und dann
/// verspräche es etwas, was nicht im Umschlag liegt.
library;

import '../models/mail_models.dart';

/// Teilt mitgegebene Anhänge in „passt in EINE Mail" und „passt nicht mehr".
///
/// Für Aufrufer, die nicht aufteilen können — den Verfassen-Bildschirm etwa,
/// der beim Weiterleiten die Anhänge der Ursprungsnachricht übernimmt. Wo
/// aufgeteilt werden darf, ist [mailSendungenPlanen] das Richtige.
///
/// ⚠️ Die Abgelehnten kommen NAMENTLICH zurück, statt fallen gelassen zu
/// werden. Genau das war der Fehler: 21 Anhänge gingen als 20 hinaus, und
/// nichts hat es gemeldet.
(List<MailOutgoingAttachment>, List<String>) mailAnhaengeEinpassen(
  List<MailOutgoingAttachment> eingang, {
  int maxDateien = kMailMaxAnhaenge,
  int maxBytes = 25 * 1024 * 1024,
}) {
  final passend = <MailOutgoingAttachment>[];
  final abgelehnt = <String>[];
  var bytes = 0;
  for (final a in eingang) {
    if (passend.length >= maxDateien || bytes + a.size > maxBytes) {
      abgelehnt.add(a.filename);
      continue;
    }
    passend.add(a);
    bytes += a.size;
  }
  return (passend, abgelehnt);
}

/// So viele Anhänge nimmt eine E-Mail.
///
/// ⚠️ Keine Höflichkeitsgrenze: PHP nimmt je Anfrage nur `max_file_uploads`
/// Dateien an und verwirft den Rest **still**. Derselbe Wert steht in
/// `mail_compose_screen.dart` als `_maxFiles`; laufen sie auseinander,
/// verschwinden Anhänge ohne Meldung.
const int kMailMaxAnhaenge = 20;

/// Eine Datei, so wie sie an die Mail gehängt wird.
class MailAnhangPlan {
  /// Id der Unterlage in der Akte — der Server baut daraus das Anschreiben.
  final int docId;

  /// Der Name, unter dem die Datei **hinausgeht**. Kommt vom Server, damit
  /// die Aufzählung im Brief und der Anhang denselben Namen tragen.
  final String name;

  final int groesse;

  const MailAnhangPlan({
    required this.docId,
    required this.name,
    required this.groesse,
  });
}

/// Eine einzelne E-Mail.
class MailSendung {
  final List<MailAnhangPlan> anhaenge;
  const MailSendung(this.anhaenge);

  int get groesse => anhaenge.fold(0, (s, a) => s + a.groesse);
}

/// Das Ergebnis der Aufteilung.
class MailSendungsPlan {
  final List<MailSendung> sendungen;

  /// Dateien, die in **keine** Sendung passen, weil sie allein schon über der
  /// Größengrenze liegen. Sie werden benannt, nicht verschwiegen.
  final List<MailAnhangPlan> zuGross;

  const MailSendungsPlan(this.sendungen, this.zuGross);

  int get teile => sendungen.length;
}

/// Teilt [anhaenge] auf so wenige Mails wie möglich auf.
///
/// [maxDateien] Anhänge und [maxBytes] Gesamtgröße je Mail.
///
/// ⚠️ Die Reihenfolge bleibt erhalten. Bei einem mehrseitigen Bescheid ist
/// sie die Seitenfolge; ein „Packen nach Größe", das besser füllt, würde die
/// Seiten über die Sendungen mischen.
MailSendungsPlan mailSendungenPlanen(
  List<MailAnhangPlan> anhaenge, {
  int maxDateien = 20,
  int maxBytes = 25 * 1024 * 1024,
}) {
  final sendungen = <MailSendung>[];
  final zuGross = <MailAnhangPlan>[];
  var laufend = <MailAnhangPlan>[];
  var bytes = 0;

  void abschliessen() {
    if (laufend.isNotEmpty) {
      sendungen.add(MailSendung(List.unmodifiable(laufend)));
      laufend = <MailAnhangPlan>[];
      bytes = 0;
    }
  }

  for (final a in anhaenge) {
    // Passt sie überhaupt in eine leere Sendung? Sonst hilft kein Umbrechen.
    if (a.groesse > maxBytes) {
      zuGross.add(a);
      continue;
    }
    final vollGenug =
        laufend.length >= maxDateien || bytes + a.groesse > maxBytes;
    if (vollGenug) abschliessen();
    laufend.add(a);
    bytes += a.groesse;
  }
  abschliessen();

  return MailSendungsPlan(List.unmodifiable(sendungen), List.unmodifiable(zuGross));
}
