/// Aufenthaltsstatus options, scoped by the member's Staatsangehörigkeit.
///
/// Sources:
/// - BAMF (Bundesamt für Migration und Flüchtlinge): bamf.de — Liste der
///   Aufenthaltstitel nach AufenthG / AsylG.
/// - Stadt Berlin / Hamburg / NRW WBS-Dienstleistungsseiten — welche
///   Aufenthaltstitel als "dauerhaft" gelten und zum WBS berechtigen.
/// - § 4-§ 38 AufenthG, § 24/§ 25 AufenthG (humanitär), § 55 AsylG
///   (Aufenthaltsgestattung), § 60a AufenthG (Duldung).
///
/// Wichtig: Die Optionen entscheiden NICHT, ob der WBS bewilligt wird —
/// das macht die Sachbearbeitung beim Amt. Wir bilden hier nur die
/// üblichen Status ab, damit der Vorsitzer im PDF das Richtige stempelt.
library;

/// EU member states (ISO codes).
const _euIso = {
  'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'GR', 'HU',
  'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK', 'SI',
  'ES', 'SE',
};

/// EWR (EEA) members beyond the EU + Switzerland (Freizügigkeitsabkommen).
const _eeaSwissIso = {'IS', 'LI', 'NO', 'CH'};

/// Membership in the Freizügigkeitsregime (EU + EWR + CH).
bool _isFreizuegig(String? isoCode) {
  if (isoCode == null) return false;
  final c = isoCode.toUpperCase();
  return _euIso.contains(c) || _eeaSwissIso.contains(c);
}

/// Return the list of Aufenthaltsstatus options that make sense for the
/// member's nationality. The first entry is the recommended default.
/// Always ends with "Sonstiges" so the admin can type a free-form value.
List<String> aufenthaltsOptionsForStaat({String? isoCode, String? bezeichnung}) {
  final iso = isoCode?.toUpperCase();
  final lower = (bezeichnung ?? '').toLowerCase();

  // 1) Deutsche Staatsangehörigkeit — no Aufenthaltstitel necessary.
  if (iso == 'DE' || lower.startsWith('deutsch')) {
    return const [
      'deutsche Staatsangehörigkeit',
      'Doppelte Staatsbürgerschaft (DE + andere)',
      'Sonstiges',
    ];
  }

  // 2) EU / EWR / Schweiz — Freizügigkeitsrecht.
  if (_isFreizuegig(iso)) {
    return const [
      'EU-/EWR-Bürger — Freizügigkeitsrecht (§ 2 FreizügG/EU)',
      'Daueraufenthaltsrecht-EU (§ 4a FreizügG/EU)',
      'Schweizer Staatsangehörige — Aufenthaltserlaubnis-CH',
      'Aufenthaltskarte für Familienangehörige (Drittstaater)',
      'Sonstiges',
    ];
  }

  // 3) Vereinigtes Königreich — Post-Brexit Sonderstatus.
  if (iso == 'GB') {
    return const [
      'Aufenthaltsdokument-GB (Art. 18 Abs. 4 Austrittsabkommen)',
      'Aufenthaltsdokument für Grenzgänger-GB',
      'Aufenthaltserlaubnis (§ 7 AufenthG)',
      'Niederlassungserlaubnis (§ 9 AufenthG)',
      'Sonstiges',
    ];
  }

  // 4) Drittstaaten — Aufenthaltstitel nach AufenthG / AsylG.
  // Special cases first.
  if (iso == 'UA' || lower.startsWith('ukrain')) {
    return const [
      'Aufenthaltserlaubnis § 24 AufenthG (Ukraine-Vertriebene)',
      'Aufenthaltserlaubnis (§ 7 AufenthG)',
      'Niederlassungserlaubnis (§ 9 AufenthG)',
      'Fiktionsbescheinigung (§ 81 Abs. 5 AufenthG)',
      'Aufenthaltsgestattung (§ 55 AsylG)',
      'Duldung (§ 60a AufenthG)',
      'Sonstiges',
    ];
  }

  // Syrien, Afghanistan, Irak, Iran etc. — Schwerpunkt humanitärer Schutz.
  if ({'SY', 'AF', 'IQ', 'IR', 'ER', 'SO'}.contains(iso)) {
    return const [
      'Anerkannte/r Flüchtling (§ 25 Abs. 1 AufenthG)',
      'Subsidiärer Schutz (§ 25 Abs. 2 Alt. 2 AufenthG)',
      'Asylberechtigt (Art. 16a GG)',
      'Aufenthaltserlaubnis aus humanitären Gründen (§ 25 Abs. 3-5 AufenthG)',
      'Niederlassungserlaubnis (§ 9 AufenthG)',
      'Aufenthaltsgestattung — Asylverfahren läuft (§ 55 AsylG)',
      'Duldung (§ 60a AufenthG)',
      'Sonstiges',
    ];
  }

  if (lower == 'staatenlos') {
    return const [
      'Aufenthaltserlaubnis für staatenlose Personen (§ 23 AufenthG)',
      'Niederlassungserlaubnis (§ 9 AufenthG)',
      'Aufenthaltsgestattung (§ 55 AsylG)',
      'Duldung (§ 60a AufenthG)',
      'Sonstiges',
    ];
  }
  if (lower == 'ungeklärt') {
    return const [
      'Ungeklärte Identität',
      'Duldung (§ 60a AufenthG)',
      'Aufenthaltsgestattung (§ 55 AsylG)',
      'Sonstiges',
    ];
  }

  // Generic Drittstaaten (Türkei, USA, China, Indien, alle anderen).
  return const [
    'Niederlassungserlaubnis (§ 9 AufenthG)',
    'Erlaubnis zum Daueraufenthalt-EU (§ 9a AufenthG)',
    'Aufenthaltserlaubnis (§ 7 AufenthG)',
    'Blaue Karte EU (§ 18b AufenthG)',
    'ICT-Karte (§ 19 AufenthG)',
    'Aufenthaltserlaubnis zur Ausbildung / Studium (§ 16 ff AufenthG)',
    'Aufenthaltserlaubnis aus familiären Gründen (§ 27 ff AufenthG)',
    'Aufenthaltserlaubnis aus humanitären Gründen (§ 25 AufenthG)',
    'Fiktionsbescheinigung (§ 81 Abs. 5 AufenthG)',
    'Visum (§ 6 AufenthG)',
    'Aufenthaltsgestattung (§ 55 AsylG)',
    'Duldung (§ 60a AufenthG)',
    'Sonstiges',
  ];
}

/// Wizard-side stores `users.aufenthaltsstatus` as a short enum key (e.g.
/// `niederlassungserlaubnis`). Vorsitzer's own dropdown stores the full
/// German legal label. To display either kind consistently in the
/// Verifizierung panel, map enum keys → labels and pass any other value
/// through unchanged.
const Map<String, String> aufenthaltsstatusKeyLabels = {
  'deutsch':                  'Deutsche Staatsangehörigkeit',
  'eu_eea_freizuegigkeit':    'EU-/EWR-Bürger — Freizügigkeitsrecht (§ 2 FreizügG/EU)',
  'aufenthaltserlaubnis':     'Aufenthaltserlaubnis (befristet, § 7 AufenthG)',
  'niederlassungserlaubnis':  'Niederlassungserlaubnis (unbefristet, § 9 AufenthG)',
  'daueraufenthalt_eu':       'Erlaubnis zum Daueraufenthalt-EU (§ 9a AufenthG)',
  'blaue_karte_eu':           'Blaue Karte EU (§ 18b AufenthG)',
  'asylberechtigt':           'Asylberechtigt (Art. 16a GG)',
  'fluechtling_gfk':          'Anerkannter Flüchtling (GFK, § 25 Abs. 2 AufenthG)',
  'subsidiaerer_schutz':      'Subsidiärer Schutz (§ 25 Abs. 2 Alt. 2 AufenthG)',
  'aufenthaltsgestattung':    'Aufenthaltsgestattung — Asylverfahren läuft (§ 55 AsylG)',
  'duldung':                  'Duldung (§ 60a AufenthG)',
  'humanitaer':               'Aufenthaltserlaubnis aus humanitären Gründen (§ 25 AufenthG)',
  'sonstige':                 'Sonstiges',
};

/// Display-safe label for any `users.aufenthaltsstatus` value.
String aufenthaltsstatusLabel(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  return aufenthaltsstatusKeyLabels[raw] ?? raw;
}
