/// Tiny transit-vocabulary dictionary for bilingual TTS announcements.
///
/// The TTS in the trip map speaks German (device voice) natively.
/// For ICD e.V. members whose muttersprache isn't German, we optionally
/// add a second announcement in their language after a short delay.
///
/// Design choice: we DO NOT translate proper station names ("Rathaus" stays
/// as "Rathaus" — you can't guess what "Justizgebäude" means). We translate
/// only the frame ("Nächste Haltestelle" / "Aussteigen") plus a handful of
/// well-known landmark kernwords ("Bahnhof", "Klinikum", "Marktplatz")
/// that appear as substrings inside the station name.
library;

class TransitTranslations {
  /// Language codes accepted for TTS. Anything else falls back to German-only.
  /// Match against normalized (lowercase, trim) User.muttersprache.
  static const supported = {'ro', 'ru', 'uk', 'tr', 'en', 'pl', 'ar'};

  /// Normalize a User.muttersprache value ("Rumänisch", "romana", "RO") to
  /// an ISO-ish two-letter code the flutter_tts setLanguage understands.
  /// Returns null when we don't have a mapping (announcement stays DE-only).
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    // Direct-code
    if (supported.contains(s)) return s;
    // Common German + native labels ICD members enter
    const aliases = {
      'rumänisch': 'ro', 'rumaenisch': 'ro', 'romana': 'ro', 'română': 'ro', 'romanian': 'ro',
      'ukrainisch': 'uk', 'ukrainian': 'uk', 'ukrainska': 'uk', 'українська': 'uk',
      'russisch': 'ru', 'russian': 'ru', 'russkij': 'ru', 'русский': 'ru',
      'türkisch': 'tr', 'turkisch': 'tr', 'turkish': 'tr', 'türkçe': 'tr',
      'englisch': 'en', 'english': 'en',
      'polnisch': 'pl', 'polski': 'pl', 'polish': 'pl',
      'arabisch': 'ar', 'arabic': 'ar', 'عربي': 'ar',
    };
    return aliases[s];
  }

  /// Full BCP-47 tag flutter_tts prefers for setLanguage.
  static String bcpForLangCode(String lang) {
    switch (lang) {
      case 'ro': return 'ro-RO';
      case 'ru': return 'ru-RU';
      case 'uk': return 'uk-UA';
      case 'tr': return 'tr-TR';
      case 'en': return 'en-US';
      case 'pl': return 'pl-PL';
      case 'ar': return 'ar-SA';
      default:   return 'de-DE';
    }
  }

  /// "Nächste Haltestelle: X" → per-language.
  static String nextStop(String lang, String stopName) {
    final localName = _localizeKernwort(lang, stopName);
    switch (lang) {
      case 'ro': return 'Următoarea stație: $localName';
      case 'ru': return 'Следующая остановка: $localName';
      case 'uk': return 'Наступна зупинка: $localName';
      case 'tr': return 'Sonraki durak: $localName';
      case 'en': return 'Next stop: $localName';
      case 'pl': return 'Następny przystanek: $localName';
      case 'ar': return 'المحطة التالية: $localName';
      default:   return 'Nächste Haltestelle: $localName';
    }
  }

  /// "Aussteigen: X!" — the critical Ausstieg-Alarm shout.
  static String getOff(String lang, String stopName) {
    final localName = _localizeKernwort(lang, stopName);
    switch (lang) {
      case 'ro': return 'Coboară la $localName!';
      case 'ru': return 'Выходите на $localName!';
      case 'uk': return 'Виходьте на $localName!';
      case 'tr': return 'İnin: $localName!';
      case 'en': return 'Get off at $localName!';
      case 'pl': return 'Wysiadaj na $localName!';
      case 'ar': return 'انزل في $localName!';
      default:   return 'Aussteigen: $localName!';
    }
  }

  /// Translate a handful of German transit kernwords that appear as
  /// substrings in station names. "Ulm Hauptbahnhof" → "Ulm Gara Centrală"
  /// for Romanian users. Only exact word matches (word-boundary), never
  /// substring — so "Bahnhofstraße" stays as-is (it's a street, not a station).
  static String _localizeKernwort(String lang, String s) {
    if (lang == 'de') return s;
    final dict = _kernwortDict[lang];
    if (dict == null || dict.isEmpty) return s;
    // Word-boundary replace, preserving the case of the surrounding text.
    var out = s;
    for (final entry in dict.entries) {
      final re = RegExp(r'\b' + RegExp.escape(entry.key) + r'\b', caseSensitive: false);
      out = out.replaceAll(re, entry.value);
    }
    return out;
  }

  // Kernwords limited to unambiguous landmarks. Anything ambiguous (Platz,
  // Straße, Weg) is intentionally NOT translated — user's brain does better
  // with the German original for navigation.
  static const _kernwortDict = <String, Map<String, String>>{
    'ro': {
      'Hauptbahnhof': 'Gara Centrală',
      'Hbf': 'Gara Centrală',
      'Bahnhof': 'gara',
      'Rathaus': 'Primăria',
      'Klinikum': 'Spitalul',
      'Krankenhaus': 'Spitalul',
      'Marktplatz': 'Piața Centrală',
      'Markt': 'piața',
      'Universität': 'Universitatea',
      'Flughafen': 'aeroportul',
      'Hafen': 'portul',
      'ZOB': 'gara de autobuz',
    },
    'ru': {
      'Hauptbahnhof': 'Главный вокзал',
      'Hbf': 'Главный вокзал',
      'Bahnhof': 'вокзал',
      'Rathaus': 'ратуша',
      'Klinikum': 'больница',
      'Krankenhaus': 'больница',
      'Marktplatz': 'рыночная площадь',
      'Universität': 'университет',
      'Flughafen': 'аэропорт',
      'ZOB': 'автовокзал',
    },
    'uk': {
      'Hauptbahnhof': 'Головний вокзал',
      'Hbf': 'Головний вокзал',
      'Bahnhof': 'вокзал',
      'Rathaus': 'ратуша',
      'Klinikum': 'лікарня',
      'Krankenhaus': 'лікарня',
      'Marktplatz': 'ринкова площа',
      'Universität': 'університет',
      'Flughafen': 'аеропорт',
      'ZOB': 'автовокзал',
    },
    'tr': {
      'Hauptbahnhof': 'Merkez Garı',
      'Hbf': 'Merkez Garı',
      'Bahnhof': 'gar',
      'Rathaus': 'Belediye',
      'Klinikum': 'hastane',
      'Krankenhaus': 'hastane',
      'Marktplatz': 'Pazar Meydanı',
      'Universität': 'üniversite',
      'Flughafen': 'havalimanı',
      'ZOB': 'otogar',
    },
    'en': {
      'Hauptbahnhof': 'Central Station',
      'Hbf': 'Central Station',
      'Bahnhof': 'station',
      'Rathaus': 'Town Hall',
      'Klinikum': 'hospital',
      'Krankenhaus': 'hospital',
      'Marktplatz': 'Market Square',
      'Universität': 'university',
      'Flughafen': 'airport',
      'ZOB': 'bus terminal',
    },
    'pl': {
      'Hauptbahnhof': 'Dworzec Główny',
      'Hbf': 'Dworzec Główny',
      'Bahnhof': 'dworzec',
      'Rathaus': 'ratusz',
      'Klinikum': 'szpital',
      'Krankenhaus': 'szpital',
      'Marktplatz': 'rynek',
      'Universität': 'uniwersytet',
      'Flughafen': 'lotnisko',
      'ZOB': 'dworzec autobusowy',
    },
    'ar': {
      'Hauptbahnhof': 'المحطة الرئيسية',
      'Hbf': 'المحطة الرئيسية',
      'Bahnhof': 'المحطة',
      'Rathaus': 'دار البلدية',
      'Klinikum': 'المستشفى',
      'Krankenhaus': 'المستشفى',
      'Universität': 'الجامعة',
      'Flughafen': 'المطار',
    },
  };
}
