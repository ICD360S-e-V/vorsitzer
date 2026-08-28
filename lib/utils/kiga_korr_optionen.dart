/// Die Auswahllisten des Schriftwechsels von Kindergarten ▸ Zahlung.
///
/// 🔴 WARUM DAS NICHT IM BILDSCHIRM STEHT: der Server bildet einen
/// unbekannten `medium`-Wert STILL auf 'brief' ab
/// (`enumWert(..., 'korr_medium', 'brief')` in
/// `api/admin/kindergarten_zahlung_manage.php`). Es gibt also keinen
/// Fehler, keine Meldung — in der Akte stünde nur „Brief", wo jemand
/// telefoniert hat, und niemand käme je darauf. Dieselbe Kopplung ist im
/// Chat-Zweig schon einmal aufgetreten; dort ist der Test die einzige
/// Stelle, an der sie überhaupt auffallen kann, weil das PHP in keinem
/// Repository liegt. Hier genauso.
library;

/// ⚠️ Schlüssel = Enum `korr_medium` auf dem Server, Wert = Beschriftung.
const kKigaKorrMedien = <String, String>{
  'brief': 'Brief',
  'einschreiben': 'Einschreiben',
  'email': 'E-Mail',
  'de_mail': 'De-Mail',
  'telefon': 'Telefonisch',
  'fax': 'Fax',
  'persoenlich': 'Persönlich',
  'sonstiges': 'Sonstiges',
};

/// ⚠️ Enum `korr_richtung`. Der Vorgabewert des Servers ist 'eingehend' —
/// deshalb ist er auch im Dialog vorbelegt: ein eingegangener Bescheid,
/// der als eigenes Schreiben abgelegt ist, dreht die Beweisrichtung um.
const kKigaKorrRichtungen = <String>['eingehend', 'ausgehend'];

/// ⚠️ Dieselbe Liste wie im übrigen Kindergarten-Zweig, PLUS `png`.
/// Bildschirmfotos eines Behördenportals und Bilder aus dem
/// Nachrichtenprogramm kommen als PNG; sie auszusperren hieße, den
/// häufigsten Beleg für einen eingegangenen Bescheid nicht ablegen zu
/// können. `kindergarten_zahlung_docs_upload.php` prüft die Endung NICHT
/// — die Grenze steht allein hier.
const kKigaKorrEndungen = <String>['pdf', 'jpg', 'jpeg', 'png'];

/// Der Endpunkt nimmt eine Datei je Aufruf; das ist die Schleifengrenze,
/// nicht eine Grenze des Servers.
const kKigaKorrMaxDateien = 20;
