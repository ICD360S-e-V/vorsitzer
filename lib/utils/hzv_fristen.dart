/// Hausarztzentrierte Versorgung (HZV, „Hausarztprogramm") nach § 73b SGB V.
///
/// Hier stehen die Bezeichnungen und die beiden Fristen, die im GESETZ stehen
/// und deshalb bei jeder Kasse gelten:
///
///  * **Widerruf — zwei Wochen.** § 73b Abs. 3 SGB V: die Teilnahmeerklärung
///    kann „innerhalb von zwei Wochen nach deren Abgabe schriftlich,
///    elektronisch oder zur Niederschrift bei der Krankenkasse ohne Angabe von
///    Gründen" widerrufen werden.
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

const hzvDokTypLabel = <String, String>{
  'teilnahmeerklaerung': 'Teilnahmeerklärung',
  'begruessung': 'Begrüßungsschreiben',
  'bestaetigung': 'Bestätigung der Kasse',
  'widerruf': 'Widerruf',
  'kuendigung': 'Kündigung',
  'sonstiges': 'Sonstiges',
};

/// Letzter Tag, an dem der Widerruf noch abgeschickt werden kann:
/// Abgabe der Teilnahmeerklärung + 14 Tage.
///
/// Rechnet auf reinen Kalendertagen (`DateTime.utc`), damit die Sommerzeit
/// nichts verschiebt — mit Ortszeit wäre ein „+14 Tage" über den Umstellungstag
/// 13 Tage und 23 Stunden und könnte einen Tag zu früh landen.
DateTime? hzvWiderrufBis(DateTime? unterschriebenAm) {
  if (unterschriebenAm == null) return null;
  final d = DateTime.utc(unterschriebenAm.year, unterschriebenAm.month, unterschriebenAm.day);
  return d.add(const Duration(days: 14));
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
    final wBis = hzvWiderrufBis(d('unterschrieben_am'));
    if (wBis != null && !h.isAfter(wBis)) {
      final tage = wBis.difference(h).inDays;
      hinweise.add(HzvHinweis(HzvHinweisArt.info,
          'Widerruf ohne Angabe von Gründen noch bis ${_fmt(wBis)} möglich '
          '(${tage == 0 ? 'heute der letzte Tag' : 'noch $tage Tag${tage == 1 ? '' : 'e'}'}) '
          '— § 73b Abs. 3 SGB V.'));
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
