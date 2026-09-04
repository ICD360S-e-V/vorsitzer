/// Die Meldebestätigung eines Bürgeramt-Vorfalls: welcher Vorfalltyp trägt
/// eine, und wie heißt sie dort.
///
/// ⚠️ Diese Zuordnung steht ZWEIMAL: hier und in `baDokArten()` in
/// `api/helpers/buergeramt_dok_lib.php` auf dem Server (das PHP liegt in
/// keinem Repo). Der Schlüssel ist der freie Text aus `_vorfallTypen` —
/// es gibt keine Aufzählung in der Datenbank. Weicht eine Seite ab,
/// verschwindet der Reiter still bzw. der Upload wird mit 400 abgewiesen,
/// ohne dass irgendetwas fehlschlägt. `test/buergeramt_dokument_test.dart`
/// hält die Liste gegen `_vorfallTypen` fest.
library;

/// Die drei Vorfallarten mit Bestätigung — Schlüssel zeichengleich zu
/// `_vorfallTypen` in `lib/widgets/behorde_einwohnermeldeamt.dart`.
const Map<String, String> kBuergeramtDokTitel = {
  'Anmeldung (Wohnsitz)': 'Meldebestätigung',
  'Ummeldung (Wohnsitz)': 'Ummeldebestätigung',
  'Abmeldung (Wohnsitz)': 'Abmeldebestätigung',
};

/// Erlaubte Dateitypen. ⚠️ Muss zu `BA_DOK_ERLAUBT` auf dem Server passen —
/// eine hier zusätzlich angebotene Endung führt zu einem 400, das für den
/// Nutzer wie ein Fehler der App aussieht.
const List<String> kBuergeramtDokEndungen = ['pdf', 'jpg', 'jpeg'];

/// Höchstgröße, gleich `BA_DOK_MAX_BYTES`.
const int kBuergeramtDokMaxBytes = 20 * 1024 * 1024;

/// Name der Bestätigung für diesen Vorfalltyp — `null`, wenn es zu diesem
/// Typ keine gibt (Personalausweis, Reisepass, Gewerbeanmeldung …).
String? buergeramtDokTitel(String? typ) => kBuergeramtDokTitel[(typ ?? '').trim()];

/// Erklärender Satz unter der Überschrift.
///
/// ⚠️ Amtlich heißt das Papier bei An- UND Ummeldung „Meldebestätigung"
/// (§ 24 Abs. 3 BMG); „Ummeldebestätigung" ist die Beschriftung im
/// Bildschirm, damit an einem Ummeldungs-Vorfall nicht „Meldebestätigung"
/// steht und man rätselt, ob der Reiter zum richtigen Vorgang gehört. Der
/// amtliche Name steht deshalb hier im Text.
String buergeramtDokHinweis(String? typ) {
  switch ((typ ?? '').trim()) {
    case 'Anmeldung (Wohnsitz)':
      return 'Die Meldebestätigung, die das Bürgeramt bei der Anmeldung ausgestellt hat.';
    case 'Ummeldung (Wohnsitz)':
      return 'Die Meldebestätigung zur Ummeldung — amtlich heißt sie ebenfalls '
          '„Meldebestätigung" (§ 24 Abs. 3 BMG).';
    case 'Abmeldung (Wohnsitz)':
      return 'Die Abmeldebestätigung, die das Bürgeramt bei der Abmeldung ausgestellt hat.';
    default:
      return '';
  }
}

/// Ist diese Datei hier zulässig? Gibt den Grund zurück, sonst `null`.
///
/// ⚠️ Ein Grund im Klartext, kein `bool`: „nichts passiert" nach dem
/// Auswählen ist für den Nutzer nicht von einem Fehler der App zu
/// unterscheiden.
String? buergeramtDokAblehnung(String dateiname, int groesse) {
  final punkt = dateiname.lastIndexOf('.');
  final ext = punkt < 0 ? '' : dateiname.substring(punkt + 1).toLowerCase();
  if (!kBuergeramtDokEndungen.contains(ext)) {
    return 'Nur PDF, JPG und JPEG — „$dateiname" geht nicht.';
  }
  if (groesse <= 0) return 'Die Datei ist leer.';
  if (groesse > kBuergeramtDokMaxBytes) {
    return 'Größer als 20 MB (${(groesse / 1024 / 1024).toStringAsFixed(1)} MB).';
  }
  return null;
}
