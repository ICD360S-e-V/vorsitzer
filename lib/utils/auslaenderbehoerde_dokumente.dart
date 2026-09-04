/// Welche Dokumente zu einem Vorfall der Ausländerbehörde gehören.
///
/// ⚠️ Diese Zuordnung steht an ZWEI Stellen: hier und in `abDokPlaetze()` in
/// `api/helpers/auslaenderbehoerde_dok_lib.php`. Das PHP liegt in keinem Repo,
/// also kann eine Abweichung nur hier auffallen — `test/auslaenderbehoerde_
/// dokument_test.dart` hält deshalb eine wörtliche Kopie der Serverliste
/// daneben. Weicht ein Name ab, verschwindet der Reiter still bzw. der Upload
/// wird mit 400 abgelehnt, was auf dem Schirm wie ein Fehler der App aussieht.
library;

import 'auslaenderbehoerde_vorfaelle.dart' show kUkraineTyp;

/// Die beiden Arten. Mehr gibt es nicht — der Server nimmt nichts anderes an.
const kAbDokTitel = 'titel';

/// ⚠️ Eigener Platz, kein Beiwerk: das Feld „Anmerkungen" (§ 78 Abs. 1 Nr. 12
/// AufenthG) steht auf der RÜCKSEITE, und dort steht, ob eine Erwerbstätigkeit
/// erlaubt ist. Ein Scan nur der Vorderseite lässt genau die Auskunft weg,
/// wegen der man das Papier aufhebt.
const kAbDokRueckseite = 'titel_rueckseite';

const kAbDokZusatzblatt = 'zusatzblatt';

/// Nur bei § 24: weil keine neue Karte ausgestellt wird, sieht die alte für
/// jeden Arbeitgeber abgelaufen aus. Die Bescheinigung über die weitere
/// Gültigkeit ist dann das einzige Papier, das den Stand belegt.
const kAbDokFortgeltung = 'fortgeltungsnachweis';

/// Ein Platz im Dokumentenreiter.
class AbDokPlatz {
  final String art;

  /// Überschrift des Feldes.
  final String titel;

  /// Wozu das Papier gut ist. Steht klein darunter — bei einem Dokument, das
  /// man Behörden und Arbeitgebern vorlegt, ist das keine Zierde.
  final String zweck;

  const AbDokPlatz(this.art, this.titel, this.zweck);
}

/// ⚠️ Der Titel des ersten Platzes hängt am Vorfalltyp: zu einer Duldung
/// gehört keine Karte, sondern ein Papier. Der Text kommt deshalb aus
/// `AbFrist.dokument` des Katalogs, soweit es einen gibt.
const kAbDokZweckTitel =
    'Die Vorderseite der Karte bzw. das Papier selbst.';

/// ⚠️ „Anmerkungen" ist der amtliche Feldname und „siehe Zusatzblatt" der
/// wörtliche Aufdruck — beides steht so da, damit der Vorsitzende auf der
/// Karte findet, wovon hier die Rede ist.
const kAbDokZweckRueckseite =
    'Hier steht unter „Anmerkungen", ob eine Erwerbstätigkeit erlaubt ist — '
    'und gegebenenfalls „siehe Zusatzblatt".';

const kAbDokZweckFortgeltung =
    'Bescheinigung über die weitere Gültigkeit. Ohne sie sieht die Karte für '
    'Arbeitgeber und Behörden abgelaufen aus, weil keine neue ausgestellt wird.';

/// ⚠️ Das Zusatzblatt trägt die Nebenbestimmungen. Auf der eAT-Karte steht bei
/// der Erwerbstätigkeit nur ein Verweis darauf; wer wissen will, ob und unter
/// welchen Bedingungen jemand arbeiten darf, muss dieses Blatt sehen. Genau
/// deshalb ist es ein eigener Platz und nicht „noch ein Anhang".
/// ⚠️ Die Farbe steht NACH dem Namen und nie allein: die
/// Aufenthaltsgestattung (§ 63 AsylG) ist ebenfalls eine grüne Klappkarte.
/// Wer nur „das grüne Blatt" sagt, bekommt von Asylsuchenden das falsche
/// Dokument. Und amtlich ist die Farbe nirgends festgelegt — sie ist Praxis,
/// kein Merkmal.
const kAbDokZweckZusatzblatt =
    'Trägt die Nebenbestimmungen: Beschäftigungserlaubnis, Bindung an einen '
    'Arbeitgeber, Wochenstunden, Wohnsitzauflage. Meist eine grüne Klappkarte. '
    'Nötig, wenn auf der Karte „siehe Zusatzblatt" steht — dann muss sie laut '
    'Behörde immer mitgeführt werden. Bitte alle bedruckten Seiten.';

/// Vorfalltypen, die eine eAT-Karte erzeugen: dort gibt es beide Plätze.
const _mitKarte = <String>{
  'Aufenthaltserlaubnis beantragen (Erstantrag)',
  'Aufenthaltserlaubnis verlängern',
  'Aufenthaltserlaubnis zum Zweck der Ausbildung oder des Studiums',
  'Aufenthaltserlaubnis für eine Beschäftigung beantragen',
  'Aufenthaltserlaubnis zur Ausübung einer selbständigen Tätigkeit',
  'Aufenthaltserlaubnis zum Zweck der Forschung',
  'Blaue Karte EU beantragen',
  'Chancenkarte beantragen',
  'Niederlassungserlaubnis beantragen',
  'Erlaubnis zum Daueraufenthalt-EU beantragen',
  'Aufenthaltskarte oder Daueraufenthaltsbescheinigung (Freizügigkeit)',
  'Familiennachzug zu Ausländern — Aufenthaltserlaubnis beantragen',
  'Familiennachzug zu Deutschen — Aufenthaltserlaubnis beantragen',
  'Nachzug weiterer Familienangehöriger',
  'Aufenthaltstitel für ein minderjähriges Kind erteilen oder verlängern',
  'Aufenthaltstitel bei Asylantrag beantragen',
  'Elektronischen Aufenthaltstitel (eAT) beantragen',
  'eAT bei neuem oder geändertem Nationalpass bestellen (Passübertrag)',
  'Aufenthaltserlaubnis nach § 24 AufenthG (vorübergehender Schutz)',
};

/// Vorfalltypen mit einem Papier, aber ohne Karte — also ohne Zusatzblatt.
const _nurPapier = <String>{
  'Aufenthaltsgestattung verlängern',
  'Duldung — Erteilung oder Verlängerung',
  'Ausbildungsduldung',
  'Beschäftigungsduldung',
  'Fiktionsbescheinigung',
  'Reiseausweis für Ausländer beantragen',
  'Reiseausweis für Flüchtlinge oder für Staatenlose beantragen',
  'Notreiseausweis für Ausländer',
  'Verpflichtungserklärung abgeben',
  'Integrationskurs — Verpflichtung oder Berechtigungsschein',
};

/// Die Plätze eines Vorfalltyps, in Anzeigereihenfolge. Leer = kein Reiter.
List<String> abDokArtenFuerTyp(String? typ) {
  final t = (typ ?? '').trim();
  if (t == kUkraineTyp) {
    return const [
      kAbDokTitel,
      kAbDokRueckseite,
      kAbDokZusatzblatt,
      kAbDokFortgeltung
    ];
  }
  if (_mitKarte.contains(t)) {
    return const [kAbDokTitel, kAbDokRueckseite, kAbDokZusatzblatt];
  }
  if (_nurPapier.contains(t)) return const [kAbDokTitel];
  return const [];
}

/// Überschrift eines Platzes. Beim ersten hängt sie am Vorfalltyp — zu einer
/// Duldung gehört keine Karte, sondern ein Papier; der Name kommt dann aus dem
/// Katalog.
String abDokTitelFuerArt(String art, String? dokumentName) => switch (art) {
      kAbDokRueckseite => 'Rückseite der Karte',
      kAbDokZusatzblatt => 'Zusatzblatt zum Aufenthaltstitel',
      kAbDokFortgeltung => 'Nachweis der weiteren Gültigkeit',
      _ => dokumentName ?? 'Elektronischer Aufenthaltstitel (eAT-Karte)',
    };

String abDokZweckFuerArt(String art) => switch (art) {
      kAbDokRueckseite => kAbDokZweckRueckseite,
      kAbDokZusatzblatt => kAbDokZweckZusatzblatt,
      kAbDokFortgeltung => kAbDokZweckFortgeltung,
      _ => kAbDokZweckTitel,
    };

/// Welche Plätze leer bleiben dürfen, ohne dass etwas fehlt.
///
/// ⚠️ Das Zusatzblatt gibt es nur, WENN Nebenbestimmungen vergeben sind — ein
/// leerer Platz ist dort kein fehlendes Dokument. Ein Häkchen „vollständig"
/// wäre hier eine Behauptung, die niemand geprüft hat.
bool abDokOptional(String art) =>
    art == kAbDokZusatzblatt || art == kAbDokFortgeltung;

/// Hat dieser Typ überhaupt einen Dokumentenreiter?
bool abHatDokumente(String? typ) => abDokArtenFuerTyp(typ).isNotEmpty;

/// Erlaubte Endungen. ⚠️ Muss zu AB_DOK_ERLAUBT im Server passen — PNG ist
/// hier anders als beim Bürgeramt zugelassen (Entscheidung des Users), weil
/// die Papiere meist mit dem Telefon abfotografiert werden.
const kAbDokEndungen = <String>['pdf', 'jpg', 'jpeg', 'png'];

/// ⚠️ 20 MB, wie der Server. Steht hier, damit der Client eine zu große Datei
/// gar nicht erst hochlädt — über eine Mobilfunkleitung, deren Einbrüche wir
/// an anderer Stelle gegenüber der Telekom protokollieren, ist ein
/// abgelehnter 30-MB-Upload eine Minute Wartezeit für nichts.
const kAbDokMaxBytes = 20 * 1024 * 1024;

/// Warum eine Datei nicht in Frage kommt — `null`, wenn sie in Ordnung ist.
///
/// ⚠️ Der Dateiwähler lässt sich auf manchen Plattformen umgehen („alle
/// Dateien"). Deshalb wird hier NOCH einmal geprüft und auf dem Server ein
/// drittes Mal gegen den Inhalt, nicht nur gegen die Endung.
String? abDokAblehnung(String name, int groesse) {
  final punkt = name.lastIndexOf('.');
  final ext = punkt < 0 ? '' : name.substring(punkt + 1).toLowerCase();
  if (!kAbDokEndungen.contains(ext)) {
    return 'Nur PDF, JPG, JPEG und PNG — „$name" geht nicht.';
  }
  if (groesse <= 0) return 'Die Datei ist leer.';
  if (groesse > kAbDokMaxBytes) {
    final mb = (groesse / 1024 / 1024).toStringAsFixed(1);
    return 'Höchstens 20 MB, diese hat $mb MB.';
  }
  return null;
}
