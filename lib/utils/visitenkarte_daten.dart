import 'sprach_flaggen.dart';

/// Der Inhalt einer Visitenkarte, losgelöst vom Bildschirm.
///
/// ⚠️ Warum eine eigene Klasse und nicht einfach die Felder des Widgets: der
/// PDF-Bogen muss denselben Inhalt setzen wie die Karte auf dem Schirm, und er
/// darf dafür kein Widget bauen müssen. Ohne diese Naht wäre der Druck nur mit
/// laufender Oberfläche prüfbar — also gar nicht.
class VisitenkarteDaten {
  final String vereinsname;
  final String slogan;

  /// Vorname(n) und Nachname getrennt, weil die Karte den Nachnamen halbfett
  /// setzt — auf derselben Zeile, nicht darunter.
  final String vorname;
  final String nachname;

  final String funktion;
  final bool istGruender;
  final List<SprachAnzeige> sprachen;

  final String email;
  final String festnetz;

  /// ⚠️ Steht auf der Karte **unter** dem Festnetz — nicht, weil es dort
  /// hübsch aussieht, sondern weil die beiden Nummern zusammengehören:
  /// `+49 731 80159736` und `…37`, ein Anschluss und sein Fax. Untereinander
  /// liest man das als Paar, getrennt als zwei Zufälle.
  ///
  /// Behörden schicken durchaus noch Faxe, und ein Verein, der Menschen zu
  /// Ämtern begleitet, hat gute Gründe, eine Faxnummer zu nennen.
  final String fax;

  final String mobil;
  final String web;

  /// ⚠️ Die Mitgliedsnummer ist zugleich der **Anmeldename**
  /// (`api/auth/login_mitglied.php` nimmt sie als Benutzerkennung, mehrere
  /// Chat- und Vorstands-Endpunkte entscheiden anhand von ihr) — sie ist keine
  /// bloße Ordnungszahl.
  ///
  /// Sie stand am 13.08.2026 kurz nicht auf der Karte; **auf Entscheidung des
  /// Users steht sie wieder darauf**. Das ist keine Unachtsamkeit und wird
  /// nicht erneut aufgeworfen. Wer die Zeile das nächste Mal sieht und für
  /// einen Fehler hält: sie ist gewollt.
  final String mitgliedernummer;

  /// Anschrift ohne die c/o-Zeile, bereits einzeilig zusammengefasst.
  final String anschrift;

  /// „VR 201335 · Amtsgericht Memmingen, Bayern", schon zusammengesetzt.
  final String register;

  const VisitenkarteDaten({
    required this.vereinsname,
    required this.slogan,
    required this.vorname,
    required this.nachname,
    required this.funktion,
    required this.istGruender,
    required this.sprachen,
    required this.email,
    required this.festnetz,
    required this.fax,
    required this.mobil,
    required this.web,
    required this.mitgliedernummer,
    required this.anschrift,
    required this.register,
  });

  /// Der Inhalt des QR-Feldes: eine **vCard 3.0**.
  ///
  /// ## ⚠️ Warum nicht mehr MECARD
  ///
  /// MECARD war kürzer und damit gröber gerastert — aber es kennt **kein
  /// Faxfeld**. Ein drittes `TEL` hätte das Telefon als weitere Rufnummer
  /// gespeichert, nicht als Fax; wer die Karte scannt, bekäme drei Nummern
  /// ohne zu wissen, welche davon ein Faxgerät ist. vCard hat `TYPE=FAX`.
  ///
  /// Das kostet Dichte, und die Kante des QR-Feldes musste dafür wachsen:
  ///
  /// | Fassung | Bytes | Module | Kante für 0,40 mm/Modul |
  /// |---|---|---|---|
  /// | MECARD (ohne Fax) | 130 | 49 | 19,6 mm |
  /// | vCard 2.1 | 197 | 57 | 22,8 mm |
  /// | **vCard 3.0** | **215** | **61** | **24,4 mm** |
  ///
  /// ⚠️ **3.0 und nicht das kürzere 2.1**: vCard 2.1 kennt keine feste
  /// Zeichenkodierung, Umlaute bräuchten dort eine `CHARSET`-Angabe je Feld.
  /// Heute sind alle Namen im Vorstand ASCII — ein „Müller" im nächsten
  /// Vorstand wäre es nicht, und der Fehler fiele erst auf, wenn jemand einen
  /// zerschossenen Namen im Telefon stehen hat. 3.0 ist auf UTF-8 festgelegt.
  ///
  /// ## ⚠️ Der Doppelpunkt wird NICHT geschützt
  ///
  /// Dieselbe Lehre wie bei MECARD, am iPhone bezahlt: aus einem geschützten
  /// `https\://…` wurde dort `http://https:%5C://icd360s.de`, ein toter Link.
  /// Auswerter trennen Feld und Wert am ERSTEN Doppelpunkt; alles danach
  /// gehört zum Wert. Geschützt gehören nur `\`, `;` und `,` — sie trennen
  /// Felder und Namensteile.
  String get vcard {
    String schuetzen(String t) => t
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,')
        .replaceAll('\n', ' ');

    // ⚠️ Rufnummern international und ohne Leerzeichen. Ein Telefon legt die
    // Nummer genau so ab, wie sie im Code steht; „016094482053" wäre aus dem
    // Ausland nicht wählbar.
    String nummer(String roh) {
      var n = roh.replaceAll(RegExp(r'[^\d+]'), '');
      if (n.startsWith('00')) n = '+${n.substring(2)}';
      if (n.startsWith('0')) n = '+49${n.substring(1)}';
      return n;
    }

    final zeilen = <String>[
      'BEGIN:VCARD',
      'VERSION:3.0',
      // N trennt Nach- und Vorname — daran hängt, ob das Telefon den Kontakt
      // richtig einsortiert. FN ist der Anzeigename.
      'N:${schuetzen(nachname)};${schuetzen(vorname)};;;',
      'FN:${schuetzen('$vorname $nachname'.trim())}',
      if (vereinsname.isNotEmpty) 'ORG:${schuetzen(vereinsname)}',
      if (funktion.isNotEmpty) 'TITLE:${schuetzen(funktion)}',
      if (festnetz.isNotEmpty) 'TEL;TYPE=WORK,VOICE:${nummer(festnetz)}',
      // ⚠️ NUR `FAX`, nicht `WORK,FAX`.
      //
      // Am 14.08.2026 auf beiden Systemen geprüft: das iPhone zeigte
      // „Arbeit-Fax" richtig an, **Android nahm nur den ersten Typ** und
      // beschriftete die Nummer als „Arbeit" — das Fax war damit als Fax
      // unsichtbar, also genau die Angabe verloren, für die vCard überhaupt
      // erst MECARD abgelöst hat.
      //
      // Mit einem einzigen Typ gibt es nichts zu priorisieren. Die Einordnung
      // „geschäftlich" geht dabei verloren; das ist zu verschmerzen, denn auf
      // einer Vereinskarte ist ohnehin jede Nummer geschäftlich.
      if (fax.isNotEmpty) 'TEL;TYPE=FAX:${nummer(fax)}',
      if (mobil.isNotEmpty) 'TEL;TYPE=CELL:${nummer(mobil)}',
      if (email.isNotEmpty) 'EMAIL;TYPE=INTERNET:${schuetzen(email)}',
      if (web.isNotEmpty) 'URL:https://$web',
      'END:VCARD',
    ];
    // ⚠️ CRLF, nicht LF: die Vorschrift verlangt es, und ältere Auswerter
    // lesen sonst alles als eine Zeile.
    return zeilen.join('\r\n');
  }

}
