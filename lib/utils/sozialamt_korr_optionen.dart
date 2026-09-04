/// Die Auswahllisten des Schriftwechsels von Sozialamt ▸ Antrag ▸ Korrespondenz.
///
/// 🔴 WARUM DAS NICHT IM BILDSCHIRM STEHT: die Schlüssel sind das ENUM `weg`
/// der Tabelle `sozialamt_antrag_korrespondenz`. Weicht die Liste hier davon
/// ab, weist `api/admin/sozialamt_antrag_detail.php` den Wert mit HTTP 400 ab
/// — laut, aber eben erst zur Laufzeit und nur für den, der gerade genau
/// diesen Weg wählt. Das PHP liegt in keinem Repository, also ist
/// `test/sozialamt_korr_optionen_test.dart` die einzige Stelle im Baum, an der
/// die Kopplung überhaupt auffallen kann.
///
/// ⚠️ Der Server ersetzt einen unbekannten Weg NICHT still (anders als der
/// Kindergarten-Zweig, wo ein unbekanntes `medium` zu „Brief" wurde und
/// niemand je darauf kam). Wer hier etwas hinzufügt, ändert zuerst das ENUM.
library;

/// ⚠️ Schlüssel = ENUM `weg` auf dem Server, Wert = Beschriftung.
const kSozKorrWege = <String, String>{
  'post': 'Post (Brief)',
  'einschreiben': 'Einschreiben',
  'email': 'E-Mail',
  'de_mail': 'De-Mail',
  'online': 'Online (Portal)',
  'fax': 'Fax',
  'telefon': 'Telefonisch',
  'persoenlich': 'Persönlich',
  'sonstiges': 'Sonstiges',
};

/// Vorgabe im Dialog und Standardwert der Spalte. Papier ist beim Sozialamt
/// weiterhin der Regelfall; eine falsche Vorbelegung „Online" würde die Akte
/// über Wochen mit einem Weg füllen, den niemand gegangen ist.
const kSozKorrWegVorgabe = 'post';

/// ⚠️ Enum `richtung`. Bewusst dieselben Werte wie bisher — die beiden
/// Knöpfe „Eingang"/„Ausgang" setzen sie, sie sind nie frei wählbar.
const kSozKorrRichtungen = <String>['eingang', 'ausgang'];

/// ⚠️ Dieselbe Liste, die `sozialamt_antrag_korr_docs.php` prüft. Ein hier
/// erlaubter, dort verbotener Typ endet in einer HTTP-400 mitten in der
/// Hochladeschleife — also nach einigen bereits abgelegten Dateien.
const kSozKorrEndungen = <String>['pdf', 'jpg', 'jpeg', 'png'];

/// Der Endpunkt nimmt eine Datei je Aufruf; das ist die Schleifengrenze des
/// Clients. ⚠️ Der Server zieht dieselbe Grenze noch einmal (`KORR_MAX_DATEIEN`),
/// damit eine ältere App den Ordner nicht unbemerkt vollaufen lässt.
const kSozKorrMaxDateien = 20;
