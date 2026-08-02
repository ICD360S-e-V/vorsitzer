/// Auswahlliste für `users.muttersprache` (Verifizierung Stufe 1).
///
/// Grundlage ist die vollständige ISO-639-1-Liste (184 Codes) mit den
/// deutschen Sprachbezeichnungen, siehe
/// https://de.wikipedia.org/wiki/Liste_der_ISO-639-1-Codes
///
/// Nicht übernommen wurden zwei Gruppen, weil sie als *Muttersprache* nicht
/// vorkommen können und die Liste nur verlängern würden:
///   • Plansprachen: Esperanto, Interlingua, Interlingue, Ido, Volapük
///   • tote bzw. liturgische Sprachen: Latein, Sanskrit, Pali, Avestisch,
///     Kirchenslawisch
/// Ebenfalls draußen: `sh` (Serbokroatisch, durch bs/hr/sr abgelöst),
/// `bh` (Bihari, ein Sammelcode) sowie `nb`/`nn` — für die Frage nach der
/// Muttersprache genügt „Norwegisch", die beiden Schriftnormen zu trennen
/// verwirrt hier mehr, als es hilft.
///
/// Warum die deutsche Bezeichnung gespeichert wird und nicht der Code: die
/// bereits gepflegten Datensätze stehen so in der Datenbank („Rumanisch",
/// „Ukrainisch"), und [TransitTranslations.normalize] versteht genau diese
/// Schreibweise. Codes zu speichern hieße migrieren, ohne dass irgendwo
/// etwas besser würde.
///
/// Transkontinentale Sprachen sind dem Erdteil zugeordnet, in dem die meisten
/// Sprecher leben — Türkisch und Armenisch also Asien, Russisch Europa. Das
/// ist eine Konvention für die Sortierung, keine Aussage über Herkunft.
library;

enum Kontinent { europa, asien, afrika, amerika, ozeanien }

extension KontinentLabel on Kontinent {
  String get bezeichnung => switch (this) {
        Kontinent.europa => 'Europa',
        Kontinent.asien => 'Asien',
        Kontinent.afrika => 'Afrika',
        Kontinent.amerika => 'Amerika',
        Kontinent.ozeanien => 'Ozeanien',
      };
}

class Sprache {
  /// ISO-639-1-Code. Wird nicht gespeichert, macht die Liste aber prüfbar
  /// und erlaubt später einen Wechsel auf Codes ohne Ratespiel.
  final String code;
  final String bezeichnung;
  final Kontinent kontinent;

  /// Kommt im Verein häufig vor und steht deshalb im Erdteil oben, statt
  /// alphabetisch unterzugehen.
  final bool haeufig;

  const Sprache(this.code, this.bezeichnung, this.kontinent, {this.haeufig = false});
}

const List<Sprache> alleSprachen = [
  // ── Europa ────────────────────────────────────────────────────────────
  Sprache('de', 'Deutsch', Kontinent.europa, haeufig: true),
  Sprache('ro', 'Rumänisch', Kontinent.europa, haeufig: true),
  Sprache('ru', 'Russisch', Kontinent.europa, haeufig: true),
  Sprache('uk', 'Ukrainisch', Kontinent.europa, haeufig: true),
  Sprache('pl', 'Polnisch', Kontinent.europa, haeufig: true),
  Sprache('en', 'Englisch', Kontinent.europa, haeufig: true),
  Sprache('sq', 'Albanisch', Kontinent.europa),
  Sprache('an', 'Aragonesisch', Kontinent.europa),
  Sprache('av', 'Avarisch', Kontinent.europa),
  Sprache('ba', 'Baschkirisch', Kontinent.europa),
  Sprache('eu', 'Baskisch', Kontinent.europa),
  Sprache('be', 'Belarussisch', Kontinent.europa),
  Sprache('bs', 'Bosnisch', Kontinent.europa),
  Sprache('br', 'Bretonisch', Kontinent.europa),
  Sprache('bg', 'Bulgarisch', Kontinent.europa),
  Sprache('rm', 'Bündnerromanisch', Kontinent.europa),
  Sprache('da', 'Dänisch', Kontinent.europa),
  Sprache('et', 'Estnisch', Kontinent.europa),
  Sprache('fo', 'Färöisch', Kontinent.europa),
  Sprache('fi', 'Finnisch', Kontinent.europa),
  Sprache('fr', 'Französisch', Kontinent.europa),
  Sprache('gl', 'Galicisch', Kontinent.europa),
  Sprache('el', 'Griechisch', Kontinent.europa),
  Sprache('ga', 'Irisch', Kontinent.europa),
  Sprache('is', 'Isländisch', Kontinent.europa),
  Sprache('it', 'Italienisch', Kontinent.europa),
  Sprache('yi', 'Jiddisch', Kontinent.europa),
  Sprache('ca', 'Katalanisch', Kontinent.europa),
  Sprache('kv', 'Komi', Kontinent.europa),
  Sprache('kw', 'Kornisch', Kontinent.europa),
  Sprache('co', 'Korsisch', Kontinent.europa),
  Sprache('hr', 'Kroatisch', Kontinent.europa),
  Sprache('lv', 'Lettisch', Kontinent.europa),
  Sprache('li', 'Limburgisch', Kontinent.europa),
  Sprache('lt', 'Litauisch', Kontinent.europa),
  Sprache('lb', 'Luxemburgisch', Kontinent.europa),
  Sprache('gv', 'Manx', Kontinent.europa),
  Sprache('mt', 'Maltesisch', Kontinent.europa),
  Sprache('mk', 'Mazedonisch', Kontinent.europa),
  Sprache('nl', 'Niederländisch', Kontinent.europa),
  Sprache('se', 'Nordsamisch', Kontinent.europa),
  Sprache('no', 'Norwegisch', Kontinent.europa),
  Sprache('oc', 'Okzitanisch', Kontinent.europa),
  Sprache('os', 'Ossetisch', Kontinent.europa),
  Sprache('pt', 'Portugiesisch', Kontinent.europa),
  Sprache('sc', 'Sardisch', Kontinent.europa),
  Sprache('gd', 'Schottisch-gälisch', Kontinent.europa),
  Sprache('sv', 'Schwedisch', Kontinent.europa),
  Sprache('sr', 'Serbisch', Kontinent.europa),
  Sprache('sk', 'Slowakisch', Kontinent.europa),
  Sprache('sl', 'Slowenisch', Kontinent.europa),
  Sprache('es', 'Spanisch', Kontinent.europa),
  Sprache('tt', 'Tatarisch', Kontinent.europa),
  Sprache('cs', 'Tschechisch', Kontinent.europa),
  Sprache('ce', 'Tschetschenisch', Kontinent.europa),
  Sprache('cv', 'Tschuwaschisch', Kontinent.europa),
  Sprache('hu', 'Ungarisch', Kontinent.europa),
  Sprache('cy', 'Walisisch', Kontinent.europa),
  Sprache('wa', 'Wallonisch', Kontinent.europa),
  Sprache('fy', 'Westfriesisch', Kontinent.europa),

  // ── Asien ─────────────────────────────────────────────────────────────
  Sprache('tr', 'Türkisch', Kontinent.asien, haeufig: true),
  Sprache('ar', 'Arabisch', Kontinent.asien, haeufig: true),
  Sprache('ku', 'Kurdisch', Kontinent.asien, haeufig: true),
  Sprache('fa', 'Persisch', Kontinent.asien, haeufig: true),
  Sprache('hy', 'Armenisch', Kontinent.asien),
  Sprache('az', 'Aserbaidschanisch', Kontinent.asien),
  Sprache('as', 'Assamesisch', Kontinent.asien),
  Sprache('bn', 'Bengalisch', Kontinent.asien),
  Sprache('my', 'Birmanisch', Kontinent.asien),
  Sprache('zh', 'Chinesisch', Kontinent.asien),
  Sprache('dv', 'Dhivehi', Kontinent.asien),
  Sprache('dz', 'Dzongkha', Kontinent.asien),
  Sprache('ka', 'Georgisch', Kontinent.asien),
  Sprache('gu', 'Gujarati', Kontinent.asien),
  Sprache('he', 'Hebräisch', Kontinent.asien),
  Sprache('hi', 'Hindi', Kontinent.asien),
  Sprache('id', 'Indonesisch', Kontinent.asien),
  Sprache('ja', 'Japanisch', Kontinent.asien),
  Sprache('jv', 'Javanisch', Kontinent.asien),
  Sprache('kn', 'Kannada', Kontinent.asien),
  Sprache('kr', 'Kanuri', Kontinent.asien),
  Sprache('ks', 'Kashmiri', Kontinent.asien),
  Sprache('kk', 'Kasachisch', Kontinent.asien),
  Sprache('km', 'Khmer', Kontinent.asien),
  Sprache('ky', 'Kirgisisch', Kontinent.asien),
  Sprache('ko', 'Koreanisch', Kontinent.asien),
  Sprache('lo', 'Laotisch', Kontinent.asien),
  Sprache('ms', 'Malaiisch', Kontinent.asien),
  Sprache('ml', 'Malayalam', Kontinent.asien),
  Sprache('mr', 'Marathi', Kontinent.asien),
  Sprache('mn', 'Mongolisch', Kontinent.asien),
  Sprache('ne', 'Nepali', Kontinent.asien),
  Sprache('or', 'Oriya', Kontinent.asien),
  Sprache('pa', 'Panjabi', Kontinent.asien),
  Sprache('ps', 'Paschtunisch', Kontinent.asien),
  Sprache('sd', 'Sindhi', Kontinent.asien),
  Sprache('si', 'Singhalesisch', Kontinent.asien),
  Sprache('su', 'Sundanesisch', Kontinent.asien),
  Sprache('tl', 'Tagalog', Kontinent.asien),
  Sprache('tg', 'Tadschikisch', Kontinent.asien),
  Sprache('ta', 'Tamil', Kontinent.asien),
  Sprache('te', 'Telugu', Kontinent.asien),
  Sprache('th', 'Thai', Kontinent.asien),
  Sprache('bo', 'Tibetisch', Kontinent.asien),
  Sprache('tk', 'Turkmenisch', Kontinent.asien),
  Sprache('ug', 'Uigurisch', Kontinent.asien),
  Sprache('ur', 'Urdu', Kontinent.asien),
  Sprache('uz', 'Usbekisch', Kontinent.asien),
  Sprache('vi', 'Vietnamesisch', Kontinent.asien),
  Sprache('ii', 'Yi', Kontinent.asien),
  Sprache('za', 'Zhuang', Kontinent.asien),

  // ── Afrika ────────────────────────────────────────────────────────────
  Sprache('aa', 'Afar', Kontinent.afrika),
  Sprache('af', 'Afrikaans', Kontinent.afrika),
  Sprache('ak', 'Akan', Kontinent.afrika),
  Sprache('am', 'Amharisch', Kontinent.afrika),
  Sprache('bm', 'Bambara', Kontinent.afrika),
  Sprache('ny', 'Chichewa', Kontinent.afrika),
  Sprache('ee', 'Ewe', Kontinent.afrika),
  Sprache('ff', 'Fulfulde', Kontinent.afrika),
  Sprache('ha', 'Hausa', Kontinent.afrika),
  Sprache('ig', 'Igbo', Kontinent.afrika),
  Sprache('xh', 'isiXhosa', Kontinent.afrika),
  Sprache('zu', 'isiZulu', Kontinent.afrika),
  Sprache('kg', 'Kikongo', Kontinent.afrika),
  Sprache('ki', 'Kikuyu', Kontinent.afrika),
  Sprache('lu', 'Kiluba', Kontinent.afrika),
  Sprache('rw', 'Kinyarwanda', Kontinent.afrika),
  Sprache('rn', 'Kirundi', Kontinent.afrika),
  Sprache('ln', 'Lingála', Kontinent.afrika),
  Sprache('lg', 'Luganda', Kontinent.afrika),
  Sprache('mg', 'Malagasy', Kontinent.afrika),
  Sprache('ng', 'Ndonga', Kontinent.afrika),
  Sprache('nd', 'Nord-Ndebele', Kontinent.afrika),
  Sprache('om', 'Oromo', Kontinent.afrika),
  Sprache('kj', 'oshiKwanyama', Kontinent.afrika),
  Sprache('hz', 'Otjiherero', Kontinent.afrika),
  Sprache('sg', 'Sango', Kontinent.afrika),
  Sprache('st', 'Sesotho', Kontinent.afrika),
  Sprache('tn', 'Setswana', Kontinent.afrika),
  Sprache('sn', 'Shona', Kontinent.afrika),
  Sprache('ss', 'Siswati', Kontinent.afrika),
  Sprache('so', 'Somali', Kontinent.afrika),
  Sprache('nr', 'Süd-Ndebele', Kontinent.afrika),
  Sprache('sw', 'Swahili', Kontinent.afrika),
  Sprache('ti', 'Tigrinya', Kontinent.afrika),
  Sprache('ve', 'Tshivenda', Kontinent.afrika),
  Sprache('tw', 'Twi', Kontinent.afrika),
  Sprache('wo', 'Wolof', Kontinent.afrika),
  Sprache('ts', 'Xitsonga', Kontinent.afrika),
  Sprache('yo', 'Yoruba', Kontinent.afrika),

  // ── Amerika ───────────────────────────────────────────────────────────
  Sprache('ay', 'Aymara', Kontinent.amerika),
  Sprache('cr', 'Cree', Kontinent.amerika),
  Sprache('kl', 'Grönländisch', Kontinent.amerika),
  Sprache('gn', 'Guaraní', Kontinent.amerika),
  Sprache('ht', 'Haitianisch-Kreolisch', Kontinent.amerika),
  Sprache('iu', 'Inuktitut', Kontinent.amerika),
  Sprache('ik', 'Inupiaq', Kontinent.amerika),
  Sprache('nv', 'Navajo', Kontinent.amerika),
  Sprache('oj', 'Ojibwe', Kontinent.amerika),
  Sprache('qu', 'Quechua', Kontinent.amerika),

  // ── Ozeanien ──────────────────────────────────────────────────────────
  Sprache('bi', 'Bislama', Kontinent.ozeanien),
  Sprache('ch', 'Chamorro', Kontinent.ozeanien),
  Sprache('fj', 'Fidschi', Kontinent.ozeanien),
  Sprache('ho', 'Hiri Motu', Kontinent.ozeanien),
  Sprache('mi', 'Maori', Kontinent.ozeanien),
  Sprache('mh', 'Marshallesisch', Kontinent.ozeanien),
  Sprache('na', 'Nauruisch', Kontinent.ozeanien),
  Sprache('sm', 'Samoanisch', Kontinent.ozeanien),
  Sprache('ty', 'Tahitianisch', Kontinent.ozeanien),
  Sprache('to', 'Tongaisch', Kontinent.ozeanien),
];

/// Sprachen eines Erdteils: die häufigen zuerst, der Rest alphabetisch.
/// So steht Rumänisch ganz oben und nicht zwischen Portugiesisch und Sardisch.
List<Sprache> sprachenNachKontinent(Kontinent k) {
  final liste = alleSprachen.where((s) => s.kontinent == k).toList()
    ..sort((a, b) {
      if (a.haeufig != b.haeufig) return a.haeufig ? -1 : 1;
      return a.bezeichnung.toLowerCase().compareTo(b.bezeichnung.toLowerCase());
    });
  return liste;
}

/// Alle Bezeichnungen, in der Reihenfolge der Erdteile.
List<String> get sprachenOptionen =>
    Kontinent.values.expand((k) => sprachenNachKontinent(k)).map((s) => s.bezeichnung).toList();

/// Bringt einen gespeicherten Freitext auf die Schreibweise der Liste, damit
/// „rumanisch" und „Rumanisch" nicht als zwei verschiedene Sprachen erscheinen.
/// Findet sich keine Entsprechung, bleibt der Wert unverändert — lieber die
/// Angabe des Mitglieds behalten als sie zu verbiegen.
String sprachNormalisieren(String? roh) {
  final s = (roh ?? '').trim();
  if (s.isEmpty) return '';
  final klein = s.toLowerCase();
  for (final o in alleSprachen) {
    if (o.bezeichnung.toLowerCase() == klein) return o.bezeichnung;
  }
  // Ohne Umlaut geschrieben („Rumanisch", „Turkisch") — die häufigste
  // Abweichung, weil auf manchen Tastaturen kein ä/ö/ü liegt.
  final ohne = _ohneUmlaute(klein);
  for (final o in alleSprachen) {
    if (_ohneUmlaute(o.bezeichnung.toLowerCase()) == ohne) return o.bezeichnung;
  }
  // Zweistelliger Code, falls doch einmal „ro" statt „Rumänisch" ankommt.
  for (final o in alleSprachen) {
    if (o.code == klein) return o.bezeichnung;
  }
  return s;
}

String _ohneUmlaute(String s) => s
    .replaceAll('ä', 'a')
    .replaceAll('ö', 'o')
    .replaceAll('ü', 'u')
    .replaceAll('ß', 'ss');
