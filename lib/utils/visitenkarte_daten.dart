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
    required this.mobil,
    required this.web,
    required this.mitgliedernummer,
    required this.anschrift,
    required this.register,
  });

  /// Der Inhalt des QR-Feldes: ein **MECARD**.
  ///
  /// ## Warum MECARD und nicht vCard
  ///
  /// Beides bietet die Kamera von iPhone und Android als „Kontakt speichern"
  /// an. Der Unterschied ist die Länge, und die entscheidet, ob sich der Code
  /// von Papier überhaupt scannen lässt:
  ///
  /// | Fassung | Bytes | Module | mm je Modul bei 20 mm |
  /// |---|---|---|---|
  /// | vCard 3.0 vollständig | 330 | 69 × 69 | 0,29 |
  /// | vCard 3.0 gekürzt | 207 | 57 × 57 | 0,35 |
  /// | **MECARD** | **130** | **49 × 49** | **0,41** |
  ///
  /// ⚠️ Unter etwa 0,4 mm je Modul verläuft die Tinte eines Tintendruckers auf
  /// Normalpapier so weit, dass benachbarte Module ineinanderlaufen. Die
  /// vCard-Fassungen wären auf einer selbstgedruckten Karte also schlicht
  /// nicht lesbar — nicht „grenzwertig", sondern tot. Deshalb MECARD.
  ///
  /// ⚠️ Sonderzeichen müssen mit Rückstrich geschützt werden (`\` `;` `:` `,`),
  /// sonst bricht ein Semikolon im Namen den Satz auseinander und der Scanner
  /// liest Unsinn. „Ionut-Claudiu" hat keins, ein künftiger Name vielleicht.
  String get mecard {
    // ⚠️ Der Doppelpunkt wird NICHT geschützt — entgegen der Vorschrift.
    //
    // MECARD (NTT DoCoMo) nennt `\` `;` `:` `,` als zu schützende Zeichen. Am
    // iPhone geprüft: die Kamera entschlüsselt `\:` NICHT wieder. Aus
    // `URL:https\://icd360s.de` wurde dort
    // **`http://https:%5C://icd360s.de`** — ein toter Link.
    //
    // Der Grund ist die Art, wie die Auswerter arbeiten: Feld und Wert werden
    // am ERSTEN Doppelpunkt getrennt, alles danach gehört zum Wert. Ein
    // Doppelpunkt im Wert kann also gar nichts kaputt machen und braucht
    // keinen Schutz. `;` (Feldtrenner) und `,` (Namenstrenner) schon.
    String schuetzen(String t) => t
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,');

    // ⚠️ Rufnummern OHNE Leerzeichen und in internationaler Form. Ein Telefon
    // legt die Nummer genau so ab, wie sie im Code steht; „016094482053" wäre
    // aus dem Ausland nicht wählbar, „+49 160 …" mit Leerzeichen bringt
    // manche Wählprogramme durcheinander.
    String nummer(String roh) {
      var n = roh.replaceAll(RegExp(r'[^\d+]'), '');
      if (n.startsWith('00')) n = '+${n.substring(2)}';
      if (n.startsWith('0')) n = '+49${n.substring(1)}';
      return n;
    }

    final teile = <String>[
      'N:${schuetzen(nachname)},${schuetzen(vorname)}',
      if (vereinsname.isNotEmpty) 'ORG:${schuetzen(vereinsname)}',
      // ⚠️ Beide Rufnummern. Am iPhone geprüft: die Mobilnummer kam an, das
      // Festnetz fehlte — und wer eine Karte scannt, will die Nummer, die auf
      // der Karte steht, nicht eine Auswahl daraus.
      //
      // Das kostet Dichte: mit beiden sind es 49 statt 45 Module. Deshalb ist
      // das QR-Feld auf 20 mm gewachsen (0,41 mm je Modul statt 0,37). Die
      // Rechnung steht in `_qrFeld` in visitenkarte_pdf.dart, ein Test hält
      // die Schwelle.
      if (festnetz.isNotEmpty) 'TEL:${nummer(festnetz)}',
      if (mobil.isNotEmpty) 'TEL:${nummer(mobil)}',
      if (email.isNotEmpty) 'EMAIL:${schuetzen(email)}',
      if (web.isNotEmpty) 'URL:https://$web',
    ];
    return 'MECARD:${teile.join(';')};;';
  }

  /// Die Sprachen als Kürzelzeile: `DE · RO · EN`.
  ///
  /// ⚠️ Im Druck gibt es keine Flaggen — die bundeleigene Schrift DejaVu Sans
  /// enthält die Regional-Indicator-Zeichen nicht, und keine der frei
  /// verfügbaren PDF-Schriften bildet farbige Emoji ab. Das ist kein Verlust:
  /// die Kürzel tragen die Information ohnehin allein, genau deshalb stehen sie
  /// auch auf dem Bildschirm neben der Flagge (siehe sprach_flaggen.dart).
  String get sprachZeile => sprachen.map((s) => s.kuerzel).join(' · ');
}
