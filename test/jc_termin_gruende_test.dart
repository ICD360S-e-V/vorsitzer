import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/jc_termin_gruende.dart';

/// ⚠️ Wörtliche Kopie der Server-Whitelist aus
/// `api/admin/jobcenter_av_termin_gruende.php`.
///
/// Das PHP liegt in keinem Repo — dieser Test ist die einzige Stelle, an der
/// eine Abweichung überhaupt auffallen kann. Wer den Katalog auf dem Server
/// ändert, ändert ihn hier mit.
///
/// Warum auch die BESCHRIFTUNGEN und nicht nur die Schlüssel: den Brief setzt
/// der Server aus SEINER Tabelle. Driften die Texte auseinander, hakt man in
/// der App das eine an und verschickt das andere — und das fällt niemandem auf,
/// weil beide Seiten für sich stimmig aussehen.
const Map<String, String> _serverAbsage = {
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

const Map<String, String> _serverVerschiebung = {
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

const Map<String, String> _serverWahrnehmen = {
  'mit_beistand': 'Teilnahme mit einem Beistand nach § 13 Abs. 4 SGB X',
  'mit_dolmetscher': 'Sprachmittlung durch den Beistand',
  'unterlagen': 'Die angeforderten Unterlagen werden mitgebracht',
  'barrierefreiheit': 'Es wird ein barrierefreier Zugang benötigt',
};

const List<String> _serverVerlaufArten = [
  'geplant', 'besprochen', 'telefonat', 'schreiben', 'fax', 'antwort_jc', 'sonstiges',
];

const List<String> _serverSchreibenArten = [
  'wahrnehmen', 'verschieben', 'absage', 'beistand_zurueckweisung', 'anfrage', 'fahrtkosten',
];

const Map<String, String> _serverFahrtkosten = {
  'oepnv': 'Fahrt mit öffentlichen Verkehrsmitteln (niedrigste Klasse)',
  'pkw': 'Fahrt mit dem eigenen Kraftfahrzeug, weil öffentliche Verkehrsmittel nicht oder nicht in zumutbarer Zeit erreichbar sind',
  'begleitung': 'Reisekosten einer erforderlichen Begleitperson (§ 309 Abs. 4 SGB III)',
  'vorschuss': 'Vorabzahlung, weil die Fahrt sonst nicht angetreten werden kann',
  'beleg': 'Beleg wird nachgereicht',
  'sonstiges': 'Sonstiges',
};

const Map<String, String> _serverAnfrage = {
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

void main() {
  group('Kataloge stimmen mit dem Server überein', () {
    test('Absage-Gründe: Schlüssel und Beschriftungen identisch', () {
      expect(kJcGruendeAbsage, _serverAbsage);
    });

    test('Verschiebungs-Gründe: Schlüssel und Beschriftungen identisch', () {
      expect(kJcGruendeVerschiebung, _serverVerschiebung);
    });

    test('Zusätze zur Terminbestätigung identisch', () {
      expect(kJcZusaetzeWahrnehmen, _serverWahrnehmen);
    });

    test('Anlässe der Terminanfrage identisch', () {
      expect(kJcAnlaesseAnfrage, _serverAnfrage);
    });

    test('Reisekosten-Angaben identisch', () {
      expect(kJcFahrtkosten, _serverFahrtkosten);
    });

    test('kein Katalogtext trägt ASCII-Umschreibungen', () {
      // ⚠️ Zweimal passiert: „moeglich" und „oeffentlichen" standen wörtlich im
      // gedruckten Behördenbrief. Die Texte gehen 1:1 ins PDF.
      final alle = <String>[
        ...kJcGruendeAbsage.values, ...kJcGruendeVerschiebung.values,
        ...kJcZusaetzeWahrnehmen.values, ...kJcAnlaesseAnfrage.values,
        ...kJcFahrtkosten.values, ...kJcVerlaufArten.values, ...kJcSchreibenArten.values,
      ];
      final verdaechtig = RegExp(r'\b\w*(oe|ae|ue)\w*\b');

      // PRUEFAUSDRUCK ZUERST PRUEFEN. „Keine Treffer" beweist ohne
      // Positivkontrolle gar nichts — es koennte auch heissen, dass der
      // Ausdruck nie greift.
      expect(verdaechtig.hasMatch('Fahrt mit oeffentlichen Verkehrsmitteln'), isTrue,
          reason: 'Der Pruefausdruck greift nicht — dieser Test waere wertlos');
      expect(verdaechtig.hasMatch('Zeitfenster moeglich'), isTrue);
      expect(verdaechtig.hasMatch('Fahrt mit öffentlichen Verkehrsmitteln'), isFalse,
          reason: 'Der Pruefausdruck schlaegt bei korrektem Deutsch an');

      for (final t in alle) {
        final treffer = verdaechtig.allMatches(t).map((m) => m.group(0)).toList();
        expect(treffer, isEmpty, reason: 'ASCII-Umschreibung in: $t');
      }
    });

    test('Verlauf-Arten identisch, auch in der Reihenfolge', () {
      // Reihenfolge zählt: sie ist die Reihenfolge im Auswahlfeld, und die
      // ENUM-Spalte auf dem Server hat dieselbe.
      expect(kJcVerlaufArten.keys.toList(), _serverVerlaufArten);
    });

    test('Schreiben-Arten identisch', () {
      expect(kJcSchreibenArten.keys.toSet(), _serverSchreibenArten.toSet());
    });
  });

  group('Katalog-Zuordnung', () {
    test('jeder Schreiben-Art ist der richtige Katalog zugeordnet', () {
      expect(jcKatalogFuer('absage'), kJcGruendeAbsage);
      expect(jcKatalogFuer('verschieben'), kJcGruendeVerschiebung);
      expect(jcKatalogFuer('wahrnehmen'), kJcZusaetzeWahrnehmen);
      expect(jcKatalogFuer('anfrage'), kJcAnlaesseAnfrage);
      expect(jcKatalogFuer('fahrtkosten'), kJcFahrtkosten);
    });

    test('die Beistands-Rüge hat bewusst keinen Katalog', () {
      // Dort gibt es nichts anzukreuzen: der Sachverhalt steht im Freitext,
      // der Rest des Briefes ist Gesetzestext.
      expect(jcKatalogFuer('beistand_zurueckweisung'), isEmpty);
    });
  });

  group('amtlich vs. Praxis', () {
    test('genau die vier Gründe aus Rz. 32.12 sind als amtlich markiert', () {
      // Fachliche Weisungen § 32 SGB II, BA-Zentrale FGL21, Stand 28.03.2024.
      expect(kJcAbsageAmtlich, {'au', 'vorstellung_ag', 'arbeitszeit', 'verkehr'});
      for (final k in kJcAbsageAmtlich) {
        expect(kJcGruendeAbsage.containsKey(k), isTrue, reason: '$k fehlt im Katalog');
      }
    });

    test('Praxis-Fallgruppen sind NICHT als amtlich markiert', () {
      for (final k in ['krankenhaus', 'kind_krank', 'pflege', 'gericht', 'behoerde', 'technik', 'sonstiges']) {
        expect(jcGrundAmtlich(k), isFalse, reason: '$k darf nicht als amtlich gelten');
      }
    });
  });

  group('Vorabprüfung spiegelt die Server-Prüfung', () {
    test('eine Absage ohne jeden Grund wird abgelehnt', () {
      // Ohne wichtigen Grund ist das Fernbleiben ein Meldeversäumnis — dann
      // darf die App kein Schreiben erzeugen, das etwas anderes suggeriert.
      final f = jcSchreibenPruefen(art: 'absage', gruende: const [], freitext: '');
      expect(f, isNotNull);
      expect(f, contains('§ 32 SGB II'));
    });

    test('eine Verlegung ohne Grund wird abgelehnt', () {
      expect(jcSchreibenPruefen(art: 'verschieben', gruende: const [], freitext: ''), isNotNull);
    });

    test('Freitext allein genügt als Grund', () {
      expect(jcSchreibenPruefen(art: 'absage', gruende: const [], freitext: 'Im Krankenhaus.'), isNull);
      expect(jcSchreibenPruefen(art: 'verschieben', gruende: const [], freitext: 'Schichtdienst.'), isNull);
    });

    test('„Sonstiges" ohne Freitext wird abgelehnt', () {
      expect(jcSchreibenPruefen(art: 'absage', gruende: const ['sonstiges'], freitext: ''), isNotNull);
      expect(jcSchreibenPruefen(art: 'verschieben', gruende: const ['sonstiges'], freitext: ''), isNotNull);
      expect(jcSchreibenPruefen(art: 'absage', gruende: const ['sonstiges'], freitext: 'Grund X'), isNull);
    });

    test('ein unbekannter Schlüssel wird abgelehnt, nicht durchgereicht', () {
      // Genau der Fall, der ohne diese Prüfung lautlos in HTTP 400 endet.
      expect(jcSchreibenPruefen(art: 'absage', gruende: const ['urlaub'], freitext: ''), contains('urlaub'));
    });

    test('ein Grund aus dem FALSCHEN Katalog wird abgelehnt', () {
      // 'beistand' gibt es nur bei der Verlegung, 'krankenhaus' nur bei der
      // Absage. Vertauscht wären es Gründe, die der Server nicht kennt.
      expect(jcSchreibenPruefen(art: 'absage', gruende: const ['beistand'], freitext: ''), isNotNull);
      expect(jcSchreibenPruefen(art: 'verschieben', gruende: const ['krankenhaus'], freitext: ''), isNotNull);
    });

    test('eine Terminanfrage ohne Anlass wird abgelehnt', () {
      // Sonst kommt ein Termin heraus, auf den sich niemand vorbereitet hat.
      expect(jcSchreibenPruefen(art: 'anfrage', gruende: const [], freitext: ''), isNotNull);
      expect(jcSchreibenPruefen(art: 'anfrage', gruende: const ['unterlagen'], freitext: ''), isNull);
    });

    test('ein Reisekostenantrag ohne Fahrtangabe wird abgelehnt', () {
      expect(jcSchreibenPruefen(art: 'fahrtkosten', gruende: const [], freitext: ''), isNotNull);
      expect(jcSchreibenPruefen(art: 'fahrtkosten', gruende: const ['oepnv'], freitext: ''), isNull);
    });

    test('§ 309 Abs. 4 SGB III nennt die Begleitperson — der Katalog auch', () {
      // 🔴 Steht ausdrücklich im Gesetz und wird trotzdem fast nie beantragt.
      expect(kJcFahrtkosten['begleitung'], contains('Begleitperson'));
      expect(kJcFahrtkosten['begleitung'], contains('309 Abs. 4 SGB III'));
    });

    test('die Terminbestätigung braucht keinen Grund', () {
      expect(jcSchreibenPruefen(art: 'wahrnehmen', gruende: const [], freitext: ''), isNull);
    });

    test('die Beistands-Rüge braucht keinen Grund', () {
      expect(jcSchreibenPruefen(art: 'beistand_zurueckweisung', gruende: const [], freitext: ''), isNull);
    });

    test('eine unbekannte Art wird abgelehnt', () {
      expect(jcSchreibenPruefen(art: 'kuendigung', gruende: const [], freitext: ''), isNotNull);
    });
  });

  group('Wortwahl', () {
    test('das Absage-Schreiben heißt nicht „Absage"', () {
      // Beim Meldetermin gibt es kein Wahlrecht. Ein Knopf mit „Absage" würde
      // eines behaupten — deshalb steht dort die Mitteilung eines Grundes.
      expect(kJcSchreibenArten['absage'], isNot(contains('Absage')));
      expect(kJcSchreibenArten['absage'], contains('wichtigen Grundes'));
    });
  });
}
