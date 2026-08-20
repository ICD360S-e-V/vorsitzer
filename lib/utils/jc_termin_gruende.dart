/// Jobcenter ▸ Arbeitsvermittler ▸ Termin — die Gründe-Kataloge.
///
/// ⚠️ Diese drei Karten stehen ein zweites Mal auf dem Server, in
/// `api/admin/jobcenter_av_termin_gruende.php`. Der Server weist einen
/// unbekannten Schlüssel mit HTTP 400 ab, der Client zeigt die Beschriftung —
/// laufen sie auseinander, verschwindet ein Grund lautlos: der Haken lässt sich
/// setzen, das Speichern schlägt fehl, und für den Nutzer passiert nichts.
///
/// Das PHP liegt in keinem Repo. `test/jc_termin_gruende_test.dart` hält
/// deshalb eine wörtliche Kopie der Server-Whitelist und vergleicht sie mit
/// diesen Karten — das ist die einzige Stelle, an der die Kopplung überhaupt
/// auffallen kann.
///
/// Quelle des amtlichen Kerns: Fachliche Weisungen § 32 SGB II, BA-Zentrale
/// FGL21, Stand 28.03.2024, Rz. 32.12 — „Wichtige Gründe sind insbesondere:".
library;

/// Wichtige Gründe für ein Fernbleiben.
///
/// ⚠️ Die ersten vier stehen so im amtlichen Katalog; alles darunter sind
/// anerkannte Fallgruppen aus der Praxis. [jcGrundAmtlich] unterscheidet das,
/// damit die Oberfläche keine Praxis als Gesetz ausgibt.
const Map<String, String> kJcGruendeAbsage = {
  'au': 'Nachgewiesene Arbeitsunfähigkeit (AU-Bescheinigung liegt bei)',
  'vorstellung_ag': 'Vorstellung bei einem Arbeitgeber zu einem von diesem gewünschten Termin',
  'arbeitszeit': 'Termin liegt in der Arbeitszeit, der Arbeitgeber hat nicht freigestellt',
  'verkehr': 'Unvorhergesehener Ausfall öffentlicher Verkehrsmittel',
  'krankenhaus': 'Stationärer Krankenhausaufenthalt',
  'kind_krank': 'Erkrankung des Kindes, Betreuung nicht anderweitig sicherzustellen',
  'pflege': 'Akute Pflege oder Betreuung einer/eines Angehörigen',
  'gericht': 'Gerichtstermin oder Ladung',
  'behoerde': 'Pflichttermin bei einer anderen Behörde',
  'technik': 'Technischer Ausfall beim Video-Termin',
  'sonstiges': 'Sonstiger wichtiger Grund',
};

/// Gründe für eine Terminverlegung.
///
/// ⚠️ Das sind KEINE „wichtigen Gründe" im Sinne des § 32 SGB II. Auf eine
/// Verlegung besteht kein Rechtsanspruch — wer sie beantragt und dann fernbleibt,
/// hat ein Meldeversäumnis. Der erzeugte Brief sagt das ausdrücklich.
const Map<String, String> kJcGruendeVerschiebung = {
  'vorstellung_ag': 'Vorstellungsgespräch oder Probearbeiten zur selben Zeit',
  'arbeitszeit': 'Termin liegt in der Arbeitszeit',
  'beistand': 'Begleitung und Sprachmittlung durch den Verein nur in einem bestimmten Zeitfenster möglich',
  'therapie': 'Feste Behandlungs- oder Therapiezeit',
  'pflege_betreuung': 'Betreuungs- oder Pflegezeit (Kind, Angehörige)',
  'gesundheit': 'Gesundheitliche Einschränkung zu dieser Tageszeit',
  'fahrt': 'Anfahrt mit dem ÖPNV zur genannten Uhrzeit nicht möglich',
  'ortsabwesenheit': 'Genehmigte Ortsabwesenheit',
  'sonstiges': 'Sonstiger Grund',
};

/// Zusätze zur Terminbestätigung.
const Map<String, String> kJcZusaetzeWahrnehmen = {
  'mit_beistand': 'Teilnahme mit einem Beistand nach § 13 Abs. 4 SGB X',
  'mit_dolmetscher': 'Sprachmittlung durch den Beistand',
  'unterlagen': 'Die angeforderten Unterlagen werden mitgebracht',
  'barrierefreiheit': 'Es wird ein barrierefreier Zugang benötigt',
};

/// Die vier Schlüssel, die wörtlich in Rz. 32.12 stehen.
const Set<String> kJcAbsageAmtlich = {'au', 'vorstellung_ag', 'arbeitszeit', 'verkehr'};

/// Steht dieser Absage-Grund so im amtlichen Katalog?
bool jcGrundAmtlich(String key) => kJcAbsageAmtlich.contains(key);

/// Arten eines Verlauf-Eintrags. Reihenfolge = Reihenfolge im Auswahlfeld.
const Map<String, String> kJcVerlaufArten = {
  'geplant': 'Geplant / zu besprechen',
  'besprochen': 'Besprochen',
  'telefonat': 'Telefonat',
  'schreiben': 'Schreiben',
  'fax': 'Fax',
  'antwort_jc': 'Antwort vom Jobcenter',
  'sonstiges': 'Sonstiges',
};

/// Anlässe für eine Terminanfrage — wir bitten das Jobcenter um einen Termin,
/// statt auf eine Einladung zu warten.
const Map<String, String> kJcAnlaesseAnfrage = {
  'veraenderung': 'Veränderung in den persönlichen Verhältnissen ist mitzuteilen',
  'unterlagen': 'Unterlagen sollen persönlich übergeben und besprochen werden',
  'weiterbildung': 'Weiterbildung oder Maßnahme soll besprochen werden',
  'egv': 'Kooperationsplan bzw. Eingliederungsvereinbarung',
  'bescheid': 'Rückfragen zu einem Bescheid',
  'leistung': 'Offene Frage zur Leistung (Zahlung, Nachweis, Nachzahlung)',
  'vermittlung': 'Vermittlung und Stellenangebote',
  'gesundheit': 'Gesundheitliche Einschränkungen wirken sich auf die Mitwirkung aus',
  'sonstiges': 'Sonstiger Anlass',
};

/// Die fünf Schreiben.
const Map<String, String> kJcSchreibenArten = {
  'wahrnehmen': 'Terminbestätigung',
  'verschieben': 'Bitte um Terminverlegung',
  // Bewusst nicht „Absage": das Wort behauptet ein Wahlrecht, das es beim
  // Meldetermin nicht gibt.
  'absage': 'Mitteilung eines wichtigen Grundes',
  'beistand_zurueckweisung': 'Zurückweisung des Beistands rügen',
  // ⚠️ Hängt an KEINEM Termin — sie bittet erst um einen. Deshalb steht der
  // Knopf in der Terminliste und nicht im Detailfenster eines Termins.
  'anfrage': 'Termin anfragen',
};

/// Welcher Katalog gehört zu welchem Schreiben?
Map<String, String> jcKatalogFuer(String art) => switch (art) {
      'absage' => kJcGruendeAbsage,
      'verschieben' => kJcGruendeVerschiebung,
      'wahrnehmen' => kJcZusaetzeWahrnehmen,
      'anfrage' => kJcAnlaesseAnfrage,
      _ => const {},
    };

/// Prüft, was der Server auch prüft — damit der Nutzer die Absage sofort sieht
/// und nicht erst nach dem Rundweg über HTTP 400.
///
/// Gibt `null` zurück, wenn gespeichert werden darf, sonst den Grund.
String? jcSchreibenPruefen({
  required String art,
  required List<String> gruende,
  required String freitext,
}) {
  if (!kJcSchreibenArten.containsKey(art)) return 'Unbekannte Art: $art';
  final katalog = jcKatalogFuer(art);
  for (final g in gruende) {
    if (katalog.isNotEmpty && !katalog.containsKey(g)) return 'Unbekannter Grund: $g';
  }
  final text = freitext.trim();
  if (art == 'absage' && gruende.isEmpty && text.isEmpty) {
    return 'Ohne wichtigen Grund ist das Fernbleiben ein Meldeversäumnis (§ 32 SGB II). '
        'Bitte einen Grund angeben.';
  }
  if (art == 'anfrage' && gruende.isEmpty && text.isEmpty) {
    // Ohne Anlass kommt ein Termin heraus, auf den sich niemand vorbereitet hat.
    return 'Bitte einen Anlass für die Terminanfrage angeben.';
  }
  if (art == 'verschieben' && gruende.isEmpty && text.isEmpty) {
    return 'Bitte einen Grund für die Verlegung angeben — ohne Begründung ist es nur ein Terminwunsch.';
  }
  if (gruende.contains('sonstiges') && text.isEmpty) {
    return art == 'absage'
        ? 'Bei „Sonstiger wichtiger Grund" bitte den Grund im Freitext benennen.'
        : 'Bei „Sonstiger Grund" bitte den Grund im Freitext benennen.';
  }
  return null;
}
