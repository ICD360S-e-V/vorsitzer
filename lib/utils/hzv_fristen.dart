/// Hausarztzentrierte Versorgung (HZV, „Hausarztprogramm") nach § 73b SGB V.
///
/// Hier stehen die Bezeichnungen und die beiden Fristen, die im GESETZ stehen
/// und deshalb bei jeder Kasse gelten:
///
///  * **Widerruf — zwei Wochen.** § 73b Abs. 3 SGB V: die Teilnahmeerklärung
///    kann „innerhalb von zwei Wochen nach deren Abgabe schriftlich,
///    elektronisch oder zur Niederschrift bei der Krankenkasse ohne Angabe von
///    Gründen" widerrufen werden.
///
///    ⚠️ Die Frist läuft aber **nicht zwangsläufig ab der Unterschrift**. Der
///    Satz danach lautet wörtlich: „Die Widerrufsfrist beginnt, wenn die
///    Krankenkasse dem Versicherten eine Belehrung über sein Widerrufsrecht
///    schriftlich oder elektronisch mitgeteilt hat, frühestens jedoch mit der
///    Abgabe der Teilnahmeerklärung." Maßgeblich ist also der **spätere** der
///    beiden Tage. Im Regelfall steht die Belehrung auf dem Formular selbst
///    (so bei TK und vdek), dann fallen sie zusammen; kommt sie erst per Post,
///    beginnt die Frist später. Eine Anzeige, die nur ab der Unterschrift
///    rechnet, meldet dann „abgelaufen", obwohl die Frist noch gar nicht
///    angefangen hat — der Fehler in genau der gefährlichen Richtung.
///
///    ⚠️ Nicht das **Begrüßungsschreiben**: das nennt den Beginn der Teilnahme
///    und ist keine Widerrufsbelehrung.
///  * **Mindestbindung — zwölf Monate.** Danach ist der Versicherte „an seine
///    Teilnahmeerklärung und an die Wahl seines Hausarztes mindestens ein Jahr
///    gebunden"; ein Hausarztwechsel davor geht nur aus wichtigem Grund.
///
/// ⚠️ Die **Kündigungsfrist wird bewusst NICHT gerechnet.** Sie steht im
/// jeweiligen Selektivvertrag und weicht je Kasse ab — AOK Baden-Württemberg
/// „ein Monat, frühestens zum Ablauf des jeweiligen 12-Monats-Zeitraums", TK
/// „4 Wochen zum Ende des Teilnahmejahres, danach 4 Wochen zum Ende eines
/// Kalendervierteljahres". Ein gerechnetes Datum wäre für einen Teil der Kassen
/// schlicht falsch, und zwar unauffällig falsch: es sähe genauso aus wie ein
/// richtiges. Deshalb ist die Frist ein Textfeld und der Termin ein Datum, das
/// ein Mensch einträgt.
///
/// ⚠️ Auch der **Beginn** wird nicht gerechnet. Bei der AOK BW wird die
/// Teilnahme „zum Beginn eines Quartals wirksam" und der Stichtag steht im
/// Begrüßungsschreiben, bei der TK wird er „per Anschreiben" mitgeteilt. Der
/// Beginn ist deshalb ein eingetragenes Datum, und die Mindestbindung hängt an
/// ihm — nicht am Tag der Unterschrift.
library;

const hzvStatusLabel = <String, String>{
  'eingereicht': 'Eingereicht',
  'aktiv': 'Aktiv',
  'widerrufen': 'Widerrufen',
  'gekuendigt': 'Gekündigt',
  'abgelehnt': 'Abgelehnt',
  'beendet': 'Beendet',
};

/// Reihenfolge der Auswahl — vom Anfang des Vorgangs zu seinem Ende.
const hzvStatusReihenfolge = <String>[
  'eingereicht', 'aktiv', 'widerrufen', 'gekuendigt', 'abgelehnt', 'beendet',
];

/// Ein Eintrag zählt als laufend, solange er weder widerrufen noch beendet ist.
/// Danach richtet sich der Punkt am Tab und der Zähler: „drei Einträge" wäre
/// nichtssagend, wenn zwei davon Historie sind.
bool hzvLaeuft(String? status) => status == 'eingereicht' || status == 'aktiv';

const hzvAbgabeOrtLabel = <String, String>{
  'praxis': 'In der Hausarztpraxis',
  'kasse': 'Bei der Krankenkasse',
  'online': 'Online-Portal der Kasse',
  'post': 'Per Post',
  'sonstige': 'Sonstiges',
};

/// Gründe für einen Hausarztwechsel. **Mehrere zugleich sind der Regelfall** —
/// ein Umzug und ein zerrüttetes Vertrauensverhältnis treffen oft zusammen, und
/// wer nur einen Grund nennen darf, lässt den zweiten unter den Tisch fallen.
///
/// Wortlaut aus den Verträgen, nicht erfunden: die AOK Baden-Württemberg nennt
/// die ersten vier ausdrücklich als Härtefälle, die TK-Teilnahmeerklärung nennt
/// „Wohnortwechsel, Praxisschließung oder Störung des Vertrauensverhältnisses".
const hzvWechselGrundLabel = <String, String>{
  'arzt_nicht_mehr_dabei': 'Bisheriger Hausarzt nimmt nicht mehr am Programm teil',
  'praxis_umzug': 'Praxis zieht um — Entfernung nicht zumutbar',
  'mitglied_umzug': 'Mitglied zieht um — Entfernung nicht zumutbar',
  'praxisschliessung': 'Praxisschließung oder Praxisaufgabe',
  'vertrauensverhaeltnis': 'Arzt-Patienten-Verhältnis nachhaltig gestört',
  'zweiter_hausarzt': 'Mitglied wird von einem zweiten Hausarzt behandelt',
  'regulaer': 'Regulärer Wechsel nach Ablauf der 12 Monate',
  'kassenwechsel': 'Wechsel der Krankenkasse',
  'sonstiges': 'Sonstiges (bitte im Textfeld beschreiben)',
};

/// Reihenfolge der Anzeige — die Härtefälle zuerst, weil nur sie einen Wechsel
/// VOR Ablauf der zwölf Monate tragen.
const hzvWechselGrundReihenfolge = <String>[
  'arzt_nicht_mehr_dabei', 'praxis_umzug', 'mitglied_umzug', 'praxisschliessung',
  'vertrauensverhaeltnis', 'zweiter_hausarzt', 'regulaer', 'kassenwechsel', 'sonstiges',
];

/// Gründe, die einen Wechsel **vor** Ablauf der Mindestbindung tragen.
///
/// ⚠️ `zweiter_hausarzt` steht bewusst NICHT drin. Dass jemand zu einem zweiten
/// Hausarzt geht, ist kein Härtefall, sondern ein Verstoß gegen die
/// Teilnahmebedingungen — er begründet den Wechsel nicht, er macht ihn nötig.
/// Getragen wird der vorzeitige Wechsel dann von dem Grund, der DAHINTER steht
/// (Umzug, Vertrauensverhältnis …), und den muss jemand benennen.
const hzvHaertefallGruende = <String>{
  'arzt_nicht_mehr_dabei', 'praxis_umzug', 'mitglied_umzug',
  'praxisschliessung', 'vertrauensverhaeltnis',
};

/// „Der Hausarzt übergibt einem neu gewählten Hausarzt seine ärztlichen Daten
/// über Sie nur dann, wenn Sie das wünschen." Ohne ausdrücklichen Wunsch fängt
/// die neue Praxis bei null an — deshalb wird es festgehalten und nicht geraten.
const hzvDatenweitergabeLabel = <String, String>{
  'unbekannt': 'Nicht besprochen',
  'ja': 'Ja — Unterlagen sollen an die neue Praxis',
  'nein': 'Nein — ausdrücklich nicht gewünscht',
};

const hzvDokTypLabel = <String, String>{
  'teilnahmeerklaerung': 'Teilnahmeerklärung',
  'begruessung': 'Begrüßungsschreiben',
  'bestaetigung': 'Bestätigung der Kasse',
  'widerruf': 'Widerruf',
  'kuendigung': 'Kündigung',
  'sonstiges': 'Sonstiges',
};

/// Tag, an dem die Widerrufsfrist zu laufen beginnt: der **spätere** von
/// Belehrung und Abgabe der Teilnahmeerklärung (§ 73b Abs. 3 SGB V).
///
/// Ohne [belehrungAm] wird die Abgabe genommen — der Regelfall, weil die
/// Belehrung auf dem Formular steht. Das ist eine **Annahme**, und die Anzeige
/// sagt das auch: liegt die Belehrung in Wahrheit später, ist der errechnete
/// letzte Tag zu früh.
DateTime? hzvWiderrufBeginn(DateTime? unterschriebenAm, [DateTime? belehrungAm]) {
  final tage = [unterschriebenAm, belehrungAm]
      .whereType<DateTime>()
      .map((d) => DateTime.utc(d.year, d.month, d.day))
      .toList();
  if (tage.isEmpty) return null;
  tage.sort();
  return tage.last;
}

/// Letzter Tag, an dem der Widerruf noch abgeschickt werden kann: Beginn der
/// Frist + 14 Tage.
///
/// Rechnet auf reinen Kalendertagen (`DateTime.utc`), damit die Sommerzeit
/// nichts verschiebt — mit Ortszeit wäre ein „+14 Tage" über den Umstellungstag
/// 13 Tage und 23 Stunden und könnte einen Tag zu früh landen.
DateTime? hzvWiderrufBis(DateTime? unterschriebenAm, [DateTime? belehrungAm]) {
  final start = hzvWiderrufBeginn(unterschriebenAm, belehrungAm);
  return start?.add(const Duration(days: 14));
}

/// Letzter Tag der zwölfmonatigen Mindestbindung: Beginn + 1 Jahr − 1 Tag.
///
/// ⚠️ Kein `Duration(days: 365)` — das wäre in einem Schaltjahr ein Tag zu früh.
/// Über die Kalenderfelder ist der 29.02. ausserdem sauber: `DateTime`
/// normalisiert den 29.02. + 1 Jahr in einem Nicht-Schaltjahr auf den 01.03.,
/// minus ein Tag ergibt den 28.02. — den letzten Tag des Bindungsjahres.
DateTime? hzvBindungBis(DateTime? beginnAm) {
  if (beginnAm == null) return null;
  return DateTime.utc(beginnAm.year + 1, beginnAm.month, beginnAm.day)
      .subtract(const Duration(days: 1));
}

/// Wie ein Hinweis am Eintrag einzustufen ist.
enum HzvHinweisArt { info, warnung }

class HzvHinweis {
  final HzvHinweisArt art;
  final String text;
  const HzvHinweis(this.art, this.text);
}

/// Die Hinweise zu einem Eintrag — abgeleitet, nie gespeichert.
///
/// [heute] wird hereingereicht statt hier gelesen: sonst hinge das Ergebnis am
/// Tag des Rechners und wäre nicht prüfbar.
///
/// [vorlaufTage] ist der Vorlauf, ab dem das Ende der Mindestbindung gemeldet
/// wird. 60 Tage, weil die längste uns bekannte Vorlaufpflicht zwei Monate
/// beträgt (AOK BW: die neue Teilnahmeerklärung muss „spätestens zwei Monate
/// vor Ablauf der 12 Monate" vorliegen, sonst verlängert sich die Bindung um
/// weitere zwölf Monate).
List<HzvHinweis> hzvHinweise(
  Map<String, dynamic> t, {
  required DateTime heute,
  int vorlaufTage = 60,
}) {
  final hinweise = <HzvHinweis>[];
  final status = t['status']?.toString() ?? '';
  final h = DateTime.utc(heute.year, heute.month, heute.day);

  DateTime? d(String key) {
    final s = t[key]?.toString();
    if (s == null || s.isEmpty) return null;
    final p = DateTime.tryParse(s);
    return p == null ? null : DateTime.utc(p.year, p.month, p.day);
  }

  if (hzvLaeuft(status)) {
    final belehrung = d('belehrung_am');
    final wBis = hzvWiderrufBis(d('unterschrieben_am'), belehrung);
    if (wBis != null && !h.isAfter(wBis)) {
      final tage = wBis.difference(h).inDays;
      hinweise.add(HzvHinweis(HzvHinweisArt.info,
          'Widerruf ohne Angabe von Gründen noch bis ${_fmt(wBis)} möglich '
          '(${tage == 0 ? 'heute der letzte Tag' : 'noch $tage Tag${tage == 1 ? '' : 'e'}'})'
          '${belehrung != null ? ' — ab Erhalt der Belehrung am ${_fmt(belehrung)}' : ''}. '
          'Abschicken genügt, ankommen muss er nicht rechtzeitig (§ 73b Abs. 3 SGB V).'));
    } else if (wBis != null && belehrung == null && d('unterschrieben_am') != null) {
      // ⚠️ Kein Freibrief, aber auch kein stilles „abgelaufen": ohne
      // Belehrungsdatum ist der Ablauf nur eine Annahme, und die Frist kann in
      // Wahrheit noch gar nicht angefangen haben.
      hinweise.add(HzvHinweis(HzvHinweisArt.info,
          'Widerrufsfrist rechnerisch am ${_fmt(wBis)} abgelaufen — gerechnet ab der '
          'Unterschrift, weil kein Datum für die Widerrufsbelehrung erfasst ist. '
          'Kam die Belehrung erst später per Post, läuft die Frist ab deren Erhalt '
          'und ist womöglich noch offen. Datum nachtragen.'));
    }
  }

  // Eine eingetragene Bindung schlägt die gerechnete: manche Kassen setzen sie
  // auf ein Quartalsende, und was im Begrüßungsschreiben steht, gilt.
  final bindung = d('bindung_bis') ?? hzvBindungBis(d('beginn_am'));
  if (status == 'aktiv' && bindung != null) {
    final tage = bindung.difference(h).inDays;
    if (tage < 0) {
      hinweise.add(HzvHinweis(HzvHinweisArt.info,
          'Mindestbindung seit ${_fmt(bindung)} abgelaufen — Kündigung und '
          'Hausarztwechsel sind mit der Frist der Kasse möglich.'));
    } else if (tage <= vorlaufTage) {
      hinweise.add(HzvHinweis(HzvHinweisArt.warnung,
          'Mindestbindung endet am ${_fmt(bindung)} (in $tage Tag${tage == 1 ? '' : 'en'}). '
          'Ohne rechtzeitige Kündigung verlängert sie sich um weitere 12 Monate — '
          'Frist und Vorlauf stehen im Vertrag der Kasse.'));
    }
  }

  if (status == 'gekuendigt' && d('kuendigung_zum') == null) {
    hinweise.add(const HzvHinweis(HzvHinweisArt.warnung,
        'Gekündigt, aber ohne Datum „wirksam zum". Solange das fehlt, ist nicht '
        'erkennbar, ab wann die Regelversorgung wieder gilt.'));
  }
  if (status == 'widerrufen' && d('widerruf_am') == null) {
    hinweise.add(const HzvHinweis(HzvHinweisArt.warnung,
        'Widerrufen, aber ohne Datum. Die Zwei-Wochen-Frist ist nur mit dem '
        'Absendedatum belegbar.'));
  }
  return hinweise;
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

// ══════════════════ Zwei Hausärzte ══════════════════════════════════════

/// Die HZV bindet an **genau einen** Hausarzt. Der einzige zulässige zweite ist
/// der vom Hausarzt benannte HZV-Vertretungsarzt für Urlaub und Krankheit; die
/// gleichzeitige Teilnahme an einem weiteren Hausarztprogramm ist ausgeschlossen.
///
/// Wer daneben einen zweiten Hausarzt aufsucht, verstößt gegen die
/// Teilnahmebedingungen („zuerst den gewählten Hausarzt aufsuchen, andere Ärzte
/// nur nach Überweisung"). Die Ersatzkassen-Patienteninformation schreibt die
/// Folge aus: die Kasse kann die Teilnahme kündigen und Mehrkosten geltend
/// machen. Der richtige Weg ist ein **schriftlich erklärter Hausarztwechsel**.
class HzvKonflikt {
  final HzvHinweisArt art;
  final String text;

  /// Was zu tun ist — steht getrennt, damit die Oberfläche daraus einen Knopf
  /// machen kann statt einer weiteren Textzeile, die niemand liest.
  final String? handlung;
  const HzvKonflikt(this.art, this.text, {this.handlung});
}

/// Normalisiert einen Arztnamen für den Vergleich: Kleinschreibung, ohne Titel,
/// ohne Satzzeichen und Mehrfach-Leerzeichen.
///
/// ⚠️ Nur eine **Rückfallebene**. Verglichen wird vorrangig über `arzt_id`, weil
/// zwei Praxen denselben Nachnamen tragen können und dieselbe Praxis in zwei
/// Schreibweisen erfasst sein kann. Ein Namensvergleich, der als sicher
/// ausgegeben wird, erzeugt genau die Fehlalarme, wegen derer man am Ende jede
/// Warnung wegklickt.
String hzvNameNormal(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'\b(dr|prof|med|univ|dipl)\b\.?'), ' ')
    .replaceAll(RegExp(r'[^a-zäöüß0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

/// Prüft, ob mehr als ein Hausarzt im Spiel ist.
///
/// [teilnahmen] sind die HZV-Einträge des Mitglieds, [weitereHausaerzte] die
/// zusätzlich in Gesundheit ▸ Hausarzt erfassten Praxen (zweiter, dritter …),
/// je als `{'arzt_id': int?, 'name': String}`.
///
/// Ohne laufende Teilnahme wird **nichts** gemeldet: zwei Hausärzte sind dann
/// einfach zwei Hausärzte, und keine HZV-Regel ist berührt.
List<HzvKonflikt> hzvKonflikte(
  List<Map<String, dynamic>> teilnahmen, {
  List<Map<String, dynamic>> weitereHausaerzte = const [],
}) {
  final funde = <HzvKonflikt>[];
  final laufend = teilnahmen.where((t) => hzvLaeuft(t['status']?.toString())).toList();
  if (laufend.isEmpty) return funde;

  // ── 1) Mehr als eine laufende Teilnahme
  if (laufend.length > 1) {
    final wechsel = laufend.where((t) => t['ist_wechsel'] == true).length;
    if (wechsel == 1 && laufend.length == 2) {
      funde.add(const HzvKonflikt(HzvHinweisArt.warnung,
          'Zwei laufende Teilnahmen, eine davon als Hausarztwechsel markiert — '
          'der Wechsel ist also beantragt. Solange die Kasse ihn nicht bestätigt '
          'hat, bindet die alte Teilnahme weiter. Sobald das Begrüßungsschreiben '
          'für den neuen Hausarzt da ist, den alten Eintrag auf „Beendet" setzen.',
          handlung: 'Alten Eintrag auf „Beendet" setzen, sobald bestätigt'));
    } else {
      funde.add(HzvKonflikt(HzvHinweisArt.warnung,
          '${laufend.length} laufende Teilnahmen gleichzeitig. Die HZV bindet an '
          'genau einen Hausarzt, und die gleichzeitige Teilnahme an einem weiteren '
          'Hausarztprogramm ist ausgeschlossen. Ein Eintrag ist der gültige — die '
          'übrigen gehören auf „Beendet", oder es muss ein Wechsel erklärt werden.',
          handlung: 'Klären, welcher Eintrag gilt'));
    }
  }

  // ── 2) Ein zweiter Hausarzt in der Gesundheitsakte
  if (weitereHausaerzte.isEmpty) return funde;
  final gebunden = laufend.first;
  final gebundenId = gebunden['arzt_id'] is int ? gebunden['arzt_id'] as int : null;
  final gebundenName = hzvNameNormal(gebunden['arzt_name']?.toString() ?? '');
  final vertretung = hzvNameNormal(gebunden['vertretungsarzt']?.toString() ?? '');

  for (final a in weitereHausaerzte) {
    final id = a['arzt_id'] is int ? a['arzt_id'] as int : null;
    final name = hzvNameNormal(a['name']?.toString() ?? '');
    if (name.isEmpty && id == null) continue;

    // Derselbe Arzt? Dann ist es nur eine zweite Instanz derselben Praxis.
    if (gebundenId != null && id != null && gebundenId == id) continue;
    if (gebundenId == null || id == null) {
      if (name.isNotEmpty && name == gebundenName) continue;
    }
    // Als Vertretungsarzt benannt? Dann ist er erklärt und zulässig.
    if (vertretung.isNotEmpty && name == vertretung) continue;

    final sicher = gebundenId != null && id != null;
    if (!sicher && gebundenName.isEmpty) {
      funde.add(HzvKonflikt(HzvHinweisArt.info,
          'Es ist ein weiterer Hausarzt hinterlegt (${a['name'] ?? 'ohne Namen'}), '
          'aber der HZV-Eintrag nennt weder eine Praxis aus dem Katalog noch einen '
          'Namen — ein Abgleich ist deshalb nicht möglich. Bitte den gewählten '
          'Hausarzt im HZV-Eintrag eintragen.',
          handlung: 'Hausarzt im HZV-Eintrag nachtragen'));
      continue;
    }
    funde.add(HzvKonflikt(HzvHinweisArt.warnung,
        'In der Gesundheitsakte steht ein zweiter Hausarzt: ${a['name'] ?? '?'}'
        '${sicher ? '' : ' (nur über den Namen verglichen)'}. '
        'Die HZV bindet an genau einen. Ist das der vom Hausarzt benannte '
        'HZV-Vertretungsarzt, gehört er in das Feld „Vertretungsarzt" — dann ist '
        'alles in Ordnung. Wird er als zweiter Hausarzt aufgesucht, ist das ein '
        'Verstoß gegen die Teilnahmebedingungen: die Kasse kann die Teilnahme '
        'kündigen und Mehrkosten geltend machen. Dann muss ein Hausarztwechsel '
        'schriftlich erklärt werden.',
        handlung: 'Vertretungsarzt eintragen oder Wechsel erklären'));
  }
  return funde;
}
