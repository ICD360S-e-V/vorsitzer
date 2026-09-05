/// Jobcenter ▸ Arbeitsvermittler ▸ Maßnahme (Träger).
///
/// Die Regeln stehen hier und nicht im `build`, damit ein Test sie festhalten
/// kann — dieselbe Vorgehensweise wie bei `befreiungsausweis_regel` und
/// `sb_ausweis`.
library;

/// Kurze Beschriftung des Reiters.
///
/// ⚠️ „(Träger)" ist kein Zierrat: die Bundesagentur unterscheidet MAT
/// (bei einem **T**räger) von MAG (bei einem Arbeitgeber). Fällt der Zusatz
/// weg, ist auf dem Schirm nicht mehr zu sehen, um welche der beiden es geht.
const String kMassnahmeTabTitel = 'Maßnahme (Träger)';

/// Der amtliche Wortlaut. Steht als Überschrift IM Reiter, weil er die
/// Formulierung des Zuweisungsschreibens ist und nicht verloren gehen darf —
/// die kurze Beschriftung ist unsere, nicht die des Jobcenters.
const String kMassnahmeVollTitel =
    'Zuweisung zu einer Maßnahme zur Aktivierung und beruflichen '
    'Eingliederung bei einem Träger';

const String kMassnahmeRechtsgrundlage = '§ 16 Abs. 1 SGB II i.V.m. § 45 SGB III';

/// ⚠️ Zeichengleich mit der ENUM-Spalte `jobcenter_user_massnahme.status`
/// UND mit MN_STATUS in massnahme_manage.php. Das PHP liegt in keinem Repo —
/// weicht diese Liste ab, weist der Server mit „Unbekannter Status" ab, und
/// für den Nutzer sieht das aus wie ein Fehler der App.
const List<String> kMassnahmeStatus = [
  'zugewiesen', 'angetreten', 'laufend', 'beendet', 'abgebrochen', 'abgelehnt',
];

/// ⚠️ Zeichengleich mit MN_ART in massnahme_manage.php.
const List<String> kMassnahmeArten = [
  'MAT', 'MAG', 'AVGS', 'Weiterbildung', 'sonstige',
];

const Map<String, String> kMassnahmeStatusLabel = {
  'zugewiesen': 'Zugewiesen',
  'angetreten': 'Angetreten',
  'laufend': 'Läuft',
  'beendet': 'Beendet',
  'abgebrochen': 'Abgebrochen',
  'abgelehnt': 'Abgelehnt',
};

const Map<String, String> kMassnahmeArtLabel = {
  'MAT': 'MAT — bei einem Träger',
  'MAG': 'MAG — bei einem Arbeitgeber',
  'AVGS': 'AVGS — Aktivierungs- und Vermittlungsgutschein',
  'Weiterbildung': 'Weiterbildung',
  'sonstige': 'Sonstige',
};

/// Eine Zuweisung, die den Alltag des Mitglieds gerade bestimmt.
bool massnahmeIstOffen(String? status) =>
    status == 'zugewiesen' || status == 'angetreten' || status == 'laufend';

/// Ende der Widerspruchsfrist: ein Monat ab Bekanntgabe, § 84 Abs. 1 SGG.
///
/// ⚠️ „Monat plus eins" reicht nicht: Bekanntgabe am 31.01. hat keinen
/// 31.02. Gerechnet wird auf den letzten Tag des Zielmonats geklemmt —
/// dieselbe Falle wie bei `monateVorher()` im SB-Ausweis-Cron, dort in die
/// schädliche Richtung.
///
/// Gibt `null` zurück, wenn kein Bekanntgabedatum erfasst ist. Ein fehlendes
/// Datum wird NICHT durch das Zuweisungsdatum ersetzt: die Frist läuft ab
/// Bekanntgabe, und wann der Brief ankam, weiß nur das Mitglied.
DateTime? massnahmeWiderspruchsfrist(DateTime? bekanntgabe) {
  if (bekanntgabe == null) return null;
  final jahr = bekanntgabe.month == 12 ? bekanntgabe.year + 1 : bekanntgabe.year;
  final monat = bekanntgabe.month == 12 ? 1 : bekanntgabe.month + 1;
  final letzterTag = DateTime(monat == 12 ? jahr + 1 : jahr, monat == 12 ? 1 : monat + 1, 0).day;
  return DateTime(jahr, monat, bekanntgabe.day > letzterTag ? letzterTag : bekanntgabe.day);
}

/// Nur ISO. Ein leeres Feld heißt „nicht erfasst" und wird nicht geraten.
DateTime? massnahmeDatum(dynamic v) {
  final s = (v ?? '').toString().trim();
  if (s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}

/// Wie viele Tage bleiben bis zum Fristende. Negativ = abgelaufen.
int? massnahmeTageBisFrist(DateTime? bekanntgabe, {DateTime? heute}) {
  final frist = massnahmeWiderspruchsfrist(bekanntgabe);
  if (frist == null) return null;
  final h = heute ?? DateTime.now();
  return frist.difference(DateTime(h.year, h.month, h.day)).inDays;
}

/// ⚠️ PDO liefert Zahlen je nach Treiber als int ODER als String zurück.
/// `as int?` würde in dem einen Fall werfen — und zwar erst auf dem Gerät.
/// Steht hier und nicht in einem der Reiter: beide brauchen es.
int? mnZahl(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/// Vorschlag für den Durchführungsort eines Angebots.
///
/// Reihenfolge ist der Punkt:
///  1. was am Angebot selbst hinterlegt ist — der Bescheid nennt den
///     Durchführungsort eigens, und er kann von jeder Anschrift abweichen;
///  2. sonst die Anschrift des STANDORTS des Trägers.
///
/// ⚠️ Niemals `rechtstraeger`: das ist der juristische Sitz und liegt oft in
/// einer anderen Stadt. Im Bescheid stehen „Adresse des Maßnahmeträgers" und
/// „Durchführungsort" als zwei getrennte Zeilen — genau weil sie auseinander-
/// fallen. Wer den Sitz einsetzt, schickt das Mitglied in die falsche Stadt.
String massnahmeOrtVorschlag(Map<String, dynamic> angebot) {
  final eigener = (angebot['durchfuehrungsort'] ?? '').toString().trim();
  if (eigener.isNotEmpty) return eigener;
  final strasse = (angebot['traeger_strasse'] ?? '').toString().trim();
  final plz = (angebot['traeger_plz'] ?? '').toString().trim();
  final ort = (angebot['traeger_ort'] ?? '').toString().trim();
  final zeile2 = [plz, ort].where((e) => e.isNotEmpty).join(' ');
  // Ohne Straße wäre „89231 Neu-Ulm" allein kein Ort, an den man geht —
  // dann lieber nichts vorschlagen als etwas Halbes.
  if (strasse.isEmpty) return '';
  return zeile2.isEmpty ? strasse : '$strasse, $zeile2';
}

/// Die Kundennummer steckt im Aktenzeichen des Jobcenters.
///
/// „481.O-819D168082" → „819D168082". Getrennt wird am letzten Bindestrich;
/// zurückgegeben wird nur, was auch wie eine Kundennummer aussieht (drei
/// Ziffern, ein Buchstabe, neun Ziffern).
///
/// ⚠️ Ohne diese Form wird NICHTS geraten. Eine falsch geratene Kundennummer
/// stünde später in einem Widerspruch und wäre dort schlimmer als ein leeres
/// Feld, das jemandem auffällt.
String massnahmeKundennummerAus(String aktenzeichen) {
  final teil = aktenzeichen.split('-').last.trim();
  // Form der BA-Kundennummer: drei Ziffern, ein Buchstabe, dann Ziffern.
  // ⚠️ Die Zifferngruppe ist NICHT neunstellig — im echten Bescheid sind es
  // sechs. Eine zu enge Prüfung hätte die Nummer stillschweigend verworfen.
  return RegExp(r'^\d{3}[A-Z]\d{6,10}$').hasMatch(teil) ? teil : '';
}

/// Ende einer Maßnahme aus Beginn und Laufzeit.
///
/// ⚠️ Nur ein VORSCHLAG. Der Bescheid nennt das Ende ausdrücklich, und es kann
/// von der Katalogdauer abweichen (Feiertage, verkürzte Durchgänge). Ein
/// eingetragenes Ende wird deshalb nie überschrieben.
DateTime? massnahmeEndeVorschlag(DateTime? beginn, dynamic dauerWochen) {
  final w = mnZahl(dauerWochen);
  if (beginn == null || w == null || w <= 0) return null;
  // ⚠️ NICHT add(Duration): das rechnet in absoluter Zeit und verliert bei der
  // Zeitumstellung eine Stunde — aus dem 29.11. wird der 28.11. um 23:00.
  // Der Konstruktor normalisiert kalendarisch und ist gegen DST immun.
  return DateTime(beginn.year, beginn.month, beginn.day + w * 7 - 1);
}
