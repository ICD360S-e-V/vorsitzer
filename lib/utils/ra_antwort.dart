/// Lesehilfen für die Antworten des Rechtsanwalt-Endpunkts.
///
/// ⚠️ WARUM ES DIESE DATEI GIBT
///
/// `jsonResponse()` auf dem Server baut die Antwort mit `array_merge` —
/// die Nutzdaten landen in der **Wurzel**, nicht unter einem Schlüssel
/// `data`:
///
/// ```php
/// $response = ['success' => $success];
/// if (!empty($data)) $response = array_merge($response, $data);
/// ```
///
/// Also `{"success":true,"items":[…]}`, nicht `{"success":true,"data":{…}}`.
/// Genau daran ist der Inkasso-Zweig schon einmal gescheitert: dort wurde
/// erst `res['data']` ausgepackt und dann `data['exists']` geprüft — und
/// weil `exists` in der Wurzel steht, sah gespeicherte Arbeit wie „nichts
/// gespeichert" aus.
///
/// Zwei Aktionen liefern zusätzlich einen **echten** Schlüssel `data`
/// (`get_mandat`, `get_mahnverfahren`), weil sie ihn selbst so setzen. Es
/// gibt also beide Formen im selben Endpunkt. Deshalb lesen [raListe] und
/// [raKarte] **beide** — wie `speedtestAlsMap` es für die Speedtest-
/// Antworten tut. Nur die Serverseite anzupassen hätte nicht gereicht: die
/// Form ist ein Nebeneffekt der Schlüssel, kein Vertrag.
library;

/// Eine Liste aus der Antwort holen — egal ob sie in der Wurzel oder unter
/// `data` steht. Fehlt sie oder hat sie den falschen Typ, kommt eine leere
/// Liste zurück, nie eine Ausnahme.
///
/// ⚠️ Kein `as List` und kein `as Map`: In PHP ist ein Array mit Lücken ein
/// Objekt und ohne Lücken eine Liste, und `as Map?` auf eine Liste gibt
/// **nicht** `null` zurück, sondern wirft. Im Release-Build ist das eine
/// graue Fläche ohne Meldung.
List<Map<String, dynamic>> raListe(Map<String, dynamic> res, [String schluessel = 'items']) {
  final direkt = res[schluessel];
  if (direkt is List) {
    return direkt.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  final unten = res['data'];
  if (unten is Map && unten[schluessel] is List) {
    return (unten[schluessel] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  return const [];
}

/// Dasselbe für eine einzelne Map.
Map<String, dynamic> raKarte(Map<String, dynamic> res, String schluessel) {
  final direkt = res[schluessel];
  if (direkt is Map) return Map<String, dynamic>.from(direkt);
  final unten = res['data'];
  if (unten is Map && unten[schluessel] is Map) {
    return Map<String, dynamic>.from(unten[schluessel] as Map);
  }
  return const {};
}

/// Trimmt und macht aus `null` einen leeren String.
String raWert(dynamic v) => v?.toString().trim() ?? '';

bool raHat(dynamic v) => raWert(v).isNotEmpty;

/// `2026-08-14` → `14.08.2026`.
///
/// Leeres bleibt leer und `0000-00-00` gilt als leer — auf einem Dokument
/// über Fristen ist ein erfundenes Datum schlimmer als eine Lücke. Was sich
/// nicht parsen lässt, kommt unverändert zurück, damit nichts still
/// verschwindet.
String raDatumDe(dynamic roh) {
  final s = raWert(roh);
  if (s.isEmpty || s.startsWith('0000')) return '';
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  return '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.'
      '${d.year}';
}

/// `DateTime` → `YYYY-MM-DD`, leer bei `null`.
///
/// Der Server weist jedes andere Format mit HTTP 400 ab — auch das
/// deutsche. Absicht: `01.07.2026` an MariaDB durchgereicht wäre
/// `0000-00-00`, und das sähe aus wie „kein Datum erfasst".
String raIso(DateTime? d) => d == null ? '' : d.toIso8601String().substring(0, 10);

/// Die Statuswerte, die der Server annimmt.
///
/// ⚠️ Diese Listen sind mit `ENUMS` in `vertrag_rechtsanwalt_manage.php`
/// und mit den ENUM-Spalten in der Datenbank gekoppelt. Das PHP liegt in
/// keinem Repository — dieser Test ist die **einzige** Stelle, an der ein
/// Auseinanderlaufen überhaupt auffallen kann. Wer hier etwas hinzufügt,
/// ändert drei Stellen: Datenbankspalte, `ENUMS` im Endpunkt, diese Liste.
///
/// Ein unbekannter Wert ergibt HTTP 400 mit der Liste der erlaubten Werte —
/// nicht eine stille Kürzung auf `''`, wie MariaDB sie ohne
/// `STRICT_TRANS_TABLES` vornähme.
class RaEnums {
  const RaEnums._();

  static const mandatStatus = [
    'kein_mandat', 'mandat_erteilt', 'in_bearbeitung', 'aussergerichtlich',
    'mahnverfahren', 'klageverfahren', 'vergleich', 'ruht', 'beendet',
    'mandat_niedergelegt',
  ];

  static const aktenzeichenStatus = [
    'offen', 'in_bearbeitung', 'aussergerichtlich', 'mahnverfahren',
    'klageverfahren', 'vergleich', 'ruht', 'abgeschlossen', 'zurueckgewiesen',
  ];

  static const korrRichtung = ['eingehend', 'ausgehend'];

  static const korrMedium = [
    'brief', 'email', 'telefon', 'fax', 'bea', 'persoenlich', 'sonstiges',
  ];

  static const mahnRolle = ['antragsgegner', 'antragsteller'];

  static const mahnStufe = [
    'kein', 'mb_beantragt', 'mb_zugestellt', 'widerspruch', 'vb_beantragt',
    'vb_zugestellt', 'einspruch', 'streitverfahren', 'vollstreckung', 'erledigt',
  ];

  static const widerspruchUmfang = ['kein', 'voll', 'teil'];

  static const vollmachtStatus = [
    'draft', 'unterzeichnet', 'uebermittelt', 'widerrufen', 'abgelaufen',
  ];

  static const vollmachtWeg = ['bea', 'email', 'fax', 'post', 'persoenlich'];

  static const dokumentBereich = ['akte', 'korr', 'mahn', 'vollmacht'];
}

/// Sprachen, für die es ein übersetztes Leseexemplar der Vollmacht gibt.
///
/// ⚠️ Gekoppelt an `raVollmachtSprachen()` in
/// `api/helpers/ra_vollmacht_texte.php`. Die Grenze ist kein Zufall,
/// sondern der Zeichensatz: die Noto-Untermengen in `api/lib/fonts`
/// decken cp1250 (rumänisch), cp1251 (kyrillisch) und cp1252 (west) ab.
/// Türkisch bräuchte cp1254, Arabisch zusätzlich Rechts-nach-links und
/// Buchstabenverbindung — beides ist nicht vorhanden, und ein PDF voller
/// Fragezeichen wäre schlimmer als eines auf Deutsch.
const raUebersetzungsSprachen = ['ro', 'en', 'ru', 'uk'];

/// Der Name einer Sprache, wie ihn ein deutschsprachiger Vorstand liest.
String raSpracheName(String code) => switch (code.toLowerCase()) {
      'de' => 'Deutsch',
      'ro' => 'Rumänisch',
      'en' => 'Englisch',
      'ru' => 'Russisch',
      'uk' => 'Ukrainisch',
      'tr' => 'Türkisch',
      'ar' => 'Arabisch',
      '' => 'ohne Angabe',
      _ => code.toUpperCase(),
    };
