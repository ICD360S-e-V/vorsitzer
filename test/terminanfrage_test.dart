import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/models/user.dart';
import 'package:icd360sev_vorsitzer/utils/terminanfrage_vorlagen.dart';
import 'package:icd360sev_vorsitzer/widgets/terminanfrage_versand_dialog.dart';

/// Die 23 Tabs des Ärzte-Bildschirms, in der Reihenfolge des TabBar aus
/// `gesundheit_tab_content.dart`.
///
/// ⚠️ DIESE LISTE IST DER EIGENTLICHE TEST. Ein neu eingehängter Ärzte-Tab
/// fällt sonst nirgends auf: [arztFachFuer] gibt für einen unbekannten Typ
/// still das Auffangfach zurück, und der Brief liest sich dann allgemein
/// statt fachlich — ohne Fehler, ohne Log, ohne dass jemand es merkt.
/// Wer hier einen Tab ergänzt, muss auch ein Fach ergänzen.
const _tabs = <(String, String)>[
  ('Hausarzt', 'gesundheit_hausarzt'),
  ('Lungenarzt', 'gesundheit_lungenarzt'),
  ('Augenarzt', 'gesundheit_augenarzt'),
  ('HNO-Arzt', 'gesundheit_hno'),
  ('Psychiater', 'gesundheit_psychiater'),
  ('Kardiologe', 'gesundheit_kardiologe'),
  ('Neurologe', 'gesundheit_neurologe'),
  ('Orthopäde', 'gesundheit_orthopaede'),
  ('Hautarzt', 'gesundheit_hautarzt'),
  ('Zahnarzt', 'gesundheit_zahnarzt'),
  ('Gynäkologie', 'gesundheit_gynaekologie'),
  ('Urologie', 'gesundheit_urologie'),
  ('Onkologie', 'gesundheit_onkologie'),
  ('Endokrinologie', 'gesundheit_endokrinologie'),
  ('Diabetologie', 'gesundheit_diabetologie'),
  ('Gastroenterologie', 'gesundheit_gastroenterologie'),
  ('Wundzentrum', 'gesundheit_wundzentrum'),
  ('Rheumatologie', 'gesundheit_rheumatologie'),
  ('Medizinischer Dienst', 'gesundheit_md'),
  ('Krankenhaus', 'gesundheit_krankenhaus'),
  ('Rettungsdienst', 'gesundheit_rettungsdienst'),
  ('Sanitätshaus', 'gesundheit_sanitaetshaus'),
  ('Sonstige', 'gesundheit_sonstige'),
];

TerminanfrageDaten _daten({
  String typ = 'gesundheit_gastroenterologie',
  List<String> anlaesse = const [],
  bool beleg = false,
  bool begleitung = false,
  int termine = 0,
  String letzter = '',
  String vereinsname = '',
  String fax = '',
  String mail = '',
  String tel = '',
}) =>
    TerminanfrageDaten(
      arztTyp: typ,
      vorname: 'Maria',
      nachname: 'Muster',
      anlaesse: anlaesse,
      ueberweisungLiegtVor: beleg,
      begleitung: begleitung,
      erfassteTermine: termine,
      letzterTermin: letzter,
      vereinsname: vereinsname,
      rueckantwortFax: fax,
      rueckantwortEmail: mail,
      rueckantwortTelefon: tel,
    );

String _text(TerminanfrageVorlage v, TerminanfrageDaten d) =>
    terminanfrageText(v, d).absaetze.join('\n');

void main() {
  group('Deckung der Ärzte-Tabs', () {
    test('jeder Tab mit Anfrage-Knopf hat ein Fach', () {
      final fehlend = _tabs
          .where((t) => t.$2 != rettungsdienstOhneAnfrage)
          .where((t) => !kArztFaecher.containsKey(t.$2))
          .map((t) => t.$1)
          .toList();
      expect(fehlend, isEmpty,
          reason: 'Ohne Fach fällt der Tab still auf den Auffangtext zurück');
    });

    test('Rettungsdienst hat bewusst KEIN Fach', () {
      // Der Rettungsdienst wird über 112 disponiert und vergibt keine
      // Termine. Wer hier ein Fach ergänzt, baut eine Funktion, die im
      // Ernstfall Zeit kostet.
      expect(kArztFaecher.containsKey(rettungsdienstOhneAnfrage), isFalse);
    });

    test('jedes Fach bietet mindestens fünf Gründe an', () {
      for (final e in kArztFaecher.entries) {
        expect(e.value.anlaesse.length, greaterThanOrEqualTo(5),
            reason: '${e.key} hat zu wenige Anlässe — dann tippt jemand');
      }
    });

    test('kein Fach fällt auf den Auffangtext zurück', () {
      // ⚠️ Prüft, dass die Schlüssel wirklich passen. Ein Tippfehler im
      // Schlüssel wäre sonst unsichtbar: die Map hätte 22 Einträge, aber der
      // Tab bekäme trotzdem den allgemeinen Text.
      for (final (name, typ) in _tabs) {
        if (typ == rettungsdienstOhneAnfrage) continue;
        if (typ == 'gesundheit_sonstige') continue;
        expect(arztFachFuer(typ).erstAnlass,
            isNot(arztFachFuer('unbekannter_typ').erstAnlass),
            reason: '$name landet auf dem Auffangfach');
      }
    });
  });

  group('Vorgeschichte aus der Terminliste', () {
    final heute = DateTime(2026, 8, 20);

    test('eine offene Anfrage zählt NICHT als früherer Termin', () {
      // 🔴 Der Kern: eine Anfrage ist eine Bitte, oft unbeantwortet. Aus ihr
      // „der Patient war schon hier" zu machen, kehrt die Wahrheit um.
      final (n, wann) = terminanfrageHistorie(
          [{'datum': '2026-07-01', 'typ': 'anfrage'}], heute: heute);
      expect(n, 0);
      expect(wann, '');
      expect(vorgewaehlteVorlage(n), TerminanfrageVorlage.erstvorstellung);
    });

    test('ein Termin in der Zukunft belegt keine Vorgeschichte', () {
      final (n, _) = terminanfrageHistorie(
          [{'datum': '2026-09-05', 'typ': 'normal'}], heute: heute);
      expect(n, 0);
    });

    test('stattgefundene Termine zählen, der jüngste wird genannt', () {
      final (n, wann) = terminanfrageHistorie([
        {'datum': '2025-11-14', 'typ': 'normal'},
        {'datum': '2026-02-12', 'typ': 'notfall'},
        {'datum': '2026-07-01', 'typ': 'anfrage'},
        {'datum': '2026-09-05', 'typ': 'normal'},
      ], heute: heute);
      expect(n, 2);
      expect(wann, '12.02.2026');
      expect(vorgewaehlteVorlage(n), TerminanfrageVorlage.kontrolle);
    });
  });

  group('Was der Brief behauptet — und was nicht', () {
    test('ohne erfassten Termin wird NICHT „neuer Patient" behauptet', () {
      final t = _text(TerminanfrageVorlage.erstvorstellung, _daten());
      expect(t, contains('ist hier nicht bekannt'));
      expect(t, contains('Bitte prüfen Sie das'));
      expect(t.toLowerCase(), isNot(contains('war noch nie')));
    });

    test('mit erfasstem Termin steht ein Datum, keine Behandlungsbehauptung',
        () {
      final t = _text(TerminanfrageVorlage.kontrolle,
          _daten(termine: 3, letzter: '12.02.2026'));
      expect(t, contains('zuletzt am 12.02.2026'));
      // ⚠️ Eine erfasste Terminzeile belegt keinen Behandlungsverlauf.
      expect(t, isNot(contains('in Behandlung gewesen')));
    });

    test('die Überweisung wird nur zugesagt, wenn sie bestätigt ist', () {
      expect(_text(TerminanfrageVorlage.erstvorstellung, _daten(beleg: false)),
          isNot(contains('liegt vor')));
      expect(_text(TerminanfrageVorlage.erstvorstellung, _daten(beleg: true)),
          contains('Überweisung liegt vor'));
    });

    test('beim Sanitätshaus heißt der Beleg Rezept und nennt die Frist', () {
      final t = _text(TerminanfrageVorlage.erstvorstellung,
          _daten(typ: 'gesundheit_sanitaetshaus', beleg: true));
      expect(t, contains('ärztliche Verordnung (Rezept)'));
      expect(t, contains('28 Kalendertage'));
      expect(t, isNot(contains('Überweisung')));
    });

    test('beim Akuttermin entfällt der Absatz über die Aktenlage', () {
      final t = _text(TerminanfrageVorlage.akut, _daten());
      expect(t, isNot(contains('ist hier nicht bekannt')));
      expect(t, contains('kurzfristigen Termin'));
    });
  });

  group('Gründe werden grammatisch richtig eingereiht', () {
    test('Beschwerden und Anliegen stehen in getrennten Sätzen', () {
      // ⚠️ „Es bestehen eine professionelle Zahnreinigung" wäre der Fehler,
      // den diese Trennung verhindert.
      final t = _text(
        TerminanfrageVorlage.kontrolle,
        _daten(anlaesse: [
          'Sodbrennen / saures Aufstoßen',
          'Blut im Stuhl',
          'Vorsorge-Darmspiegelung',
        ]),
      );
      expect(t, contains('Es bestehen Sodbrennen'));
      expect(t, contains('sowie Blut im Stuhl'));
      expect(t, contains('Anlass ist die Vorsorge-Darmspiegelung'));
    });

    test('ein einzelner Grund bekommt den Singular', () {
      final t = _text(TerminanfrageVorlage.kontrolle,
          _daten(anlaesse: ['Blut im Stuhl']));
      expect(t, contains('Es besteht Blut im Stuhl.'));
    });

    test('ein Grund, den das Fach nicht kennt, wird übergangen', () {
      // Sonst landete roher Text aus einer alten Auswahl im Brief.
      final t = _text(TerminanfrageVorlage.kontrolle,
          _daten(anlaesse: ['Zahnschmerzen']));
      expect(t, isNot(contains('Zahnschmerzen')));
    });
  });

  group('Das Zeitfenster des Vereins', () {
    test('mit Begleitung wird um einen Termin von 14 bis 17 Uhr gebeten', () {
      // 🔴 Das Fenster ist der Zeitraum, in dem jemand MITKOMMEN kann — nicht
      // die Vorliebe des Patienten. Der Brief muss den Grund mitliefern,
      // sonst liest die Praxis nur „Wunschzeit nachmittags".
      final t = _text(TerminanfrageVorlage.kontrolle,
          _daten(begleitung: true, vereinsname: 'ICD360S e.V.'));
      expect(t, contains(kVereinErreichbarkeit));
      expect(t, contains('Sprachmittlung'));
      expect(t, contains('nach Möglichkeit'));
    });

    test('ohne Begleitung keine Bitte um eine Terminlage', () {
      final t = _text(
          TerminanfrageVorlage.kontrolle, _daten(begleitung: false));
      expect(t, isNot(contains('Bitte legen Sie den Termin')));
    });

    test('die Rückrufzeit steht direkt hinter der Telefonnummer', () {
      final t = _text(TerminanfrageVorlage.kontrolle,
          _daten(tel: '0731 80159736', fax: '+49 731 80159737'));
      expect(t, contains('0731 80159736 ($kVereinErreichbarkeit)'));
    });

    test('der Verein wird als ehrenamtlich benannt', () {
      final t = _text(TerminanfrageVorlage.kontrolle,
          _daten(vereinsname: 'ICD360S e.V.', fax: '+49 731 80159737'));
      expect(t, contains('ehrenamtlich'));
    });
  });

  group('Der Rückweg richtet sich nach dem Kanal', () {
    test('im Fax steht die Faxnummer, keine Mailadresse', () {
      final t = _text(TerminanfrageVorlage.kontrolle,
          _daten(fax: '+49 731 80159737', tel: '0731 80159736'));
      expect(t, contains('per Fax an +49 731 80159737'));
      expect(t, isNot(contains('per E-Mail an')));
    });

    test('in der E-Mail steht die Adresse, keine Faxnummer', () {
      final t = _text(TerminanfrageVorlage.kontrolle,
          _daten(mail: 'icd@icd360s.de', tel: '0731 80159736'));
      expect(t, contains('per E-Mail an icd@icd360s.de'));
      expect(t, isNot(contains('per Fax an')));
    });
  });

  group('Medizinischer Dienst', () {
    test('kein Widerspruch-Grund — der gehört zur Pflegekasse', () {
      // 🔴 Widersprochen wird dem Bescheid der Pflegekasse, dort und binnen
      // eines Monats. Ein Widerspruch an den MD verbrennt die Frist.
      final gruende =
          arztFachFuer('gesundheit_md').anlaesse.map((a) => a.kurz).join(' ');
      expect(gruende.toLowerCase(), isNot(contains('widerspruch')));
      expect(gruende, contains('Gutachten anfordern'));
    });

    test('der Satz doppelt die Bitte nicht', () {
      // „bitte ich um einen Termin um Mitteilung eines Termins" war die
      // Falle: die MD-Vorlagen sind bereits als Bitte formuliert.
      final t = _text(TerminanfrageVorlage.erstvorstellung,
          _daten(typ: 'gesundheit_md'));
      expect(t, contains('hiermit bitte ich um Mitteilung eines Termins'));
      expect(t, isNot(contains('Termin um Mitteilung')));
    });

    test('keine Aktenlage-Frage — dort gibt es keine Patientenakte', () {
      final t = _text(
          TerminanfrageVorlage.kontrolle, _daten(typ: 'gesundheit_md'));
      expect(t, isNot(contains('Akte besteht')));
    });
  });

  test('jede Stelle wird richtig benannt', () {
    // ⚠️ „in Ihrer Praxis" an ein Sanitätshaus zeigt sofort, dass da ein
    // Formular gelaufen ist und kein Mensch geschrieben hat.
    expect(_text(TerminanfrageVorlage.erstvorstellung, _daten()),
        contains('in Ihrer Praxis'));
    expect(
        _text(TerminanfrageVorlage.erstvorstellung,
            _daten(typ: 'gesundheit_sanitaetshaus')),
        contains('bei Ihrem Sanitätshaus'));
    expect(
        _text(TerminanfrageVorlage.erstvorstellung,
            _daten(typ: 'gesundheit_krankenhaus')),
        contains('in Ihrem Haus'));
  });

  test('der Betreff nennt Art, Namen und Geburtsdatum', () {
    final d = TerminanfrageDaten(
        arztTyp: 'gesundheit_hausarzt',
        vorname: 'Maria',
        nachname: 'Muster',
        geburtsdatum: '14.03.1985');
    expect(terminanfrageText(TerminanfrageVorlage.akut, d).betreff,
        'Terminanfrage – kurzfristiger Termin: Maria Muster, geb. 14.03.1985');
  });

  group('Der Name auf dem Dokument', () {
    User bauUser({String? vorname, String? nachname, required String name}) =>
        User.fromJson({
          'id': 13,
          'mitgliedernummer': 'M68650',
          'email': 'm@test.de',
          'name': name,
          'vorname': vorname,
          'nachname': nachname,
          'role': 'mitglied',
          'status': 'active',
        });

    test('vollständige Angaben ergeben den vollen Namen', () {
      final d = terminanfrageDatenBauen(
        arztTyp: 'gesundheit_hausarzt',
        user: bauUser(vorname: 'Ionuț', nachname: 'Duinea', name: 'Ionuț Duinea'),
        arzt: const {},
        termine: const [],
      );
      expect(d.vollerName, 'Ionuț Duinea');
    });

    test('ohne Nachnamen wird der Name NICHT verdoppelt', () {
      // 🔴 `user.name` ist der volle Name. `user.nachname ?? user.name` ergab
      // „Ionuț" + „Ionuț Duinea" = „Ionuț Ionuț Duinea" — auf einem Dokument,
      // das später als Nachweis dienen soll.
      final d = terminanfrageDatenBauen(
        arztTyp: 'gesundheit_hausarzt',
        user: bauUser(vorname: 'Ionuț', nachname: null, name: 'Ionuț Duinea'),
        arzt: const {},
        termine: const [],
      );
      expect(d.vollerName, 'Ionuț Duinea');
    });

    test('Kanäle und Vorgeschichte kommen aus dem Arzt-Datensatz', () {
      final d = terminanfrageDatenBauen(
        arztTyp: 'gesundheit_hno',
        user: bauUser(vorname: 'Maria', nachname: 'Muster', name: 'Maria Muster'),
        arzt: const {
          'praxis_name': 'HNO Ulm',
          'email': 'praxis@hno-ulm.de',
          'fax': '0731 1234567',
        },
        termine: const [
          {'datum': '2020-05-05', 'typ': 'normal'},
          {'datum': '2020-06-06', 'typ': 'anfrage'},
        ],
      );
      expect(d.praxisEmail, 'praxis@hno-ulm.de');
      expect(d.praxisFax, '0731 1234567');
      expect(d.erfassteTermine, 1, reason: 'die Anfrage zählt nicht mit');
    });
  });

  test('ohne gewählten Kanal wird kein schriftlicher Rückweg genannt', () {
    // 🔴 Die Vorschau baute den Text früher mit dem Platzhalter „vorschau";
    // die Ausschluss-Logik ließ dabei BEIDE Rückwege durch, und der Kasten
    // „So geht es raus" zeigte etwas anderes als das Versandte. Der Dialog
    // setzt jetzt nur den gewählten Weg — dieser Test hält fest, wie sich
    // der Text verhält, wenn keiner gewählt ist.
    const d = TerminanfrageDaten(
      arztTyp: 'gesundheit_hausarzt',
      vorname: 'Maria',
      nachname: 'Muster',
      rueckantwortTelefon: '0731 80159736',
    );
    final t = terminanfrageText(TerminanfrageVorlage.kontrolle, d).absaetze
        .firstWhere((a) => a.startsWith('Bitte teilen'));
    expect(t, isNot(contains('per E-Mail an')));
    expect(t, isNot(contains('per Fax an')));
    expect(t, contains('telefonisch unter 0731 80159736'));
  });

  group('Jeder Tab speichert in SEINE Tabelle', () {
    // 🔴 Der gefährlichste Fehler dieser Änderung, und der einzige, den weder
    // `flutter analyze` noch ein Widget-Test sieht: `saveArztTermin` gibt es
    // auf dem ApiService, also kompiliert der falsche Aufruf anstandslos. Die
    // fünf entkoppelten Tabs schreiben aber in eigene Tabellen. Mit der
    // gemeinsamen Funktion ginge das Fax raus, die Meldung sagte „übergeben",
    // und der Termin landete in der falschen Tabelle — im Tab erschiene er
    // NIE, ohne Fehler und ohne Log.
    //
    // Deshalb liest dieser Test die Quelltexte. Das ist ungewöhnlich, aber es
    // ist die einzige Stelle, an der die Kopplung überhaupt auffallen kann.
    const erwartet = {
      'lib/widgets/gesundheit_tab_content.dart': 'saveArztTermin',
      'lib/widgets/mitgliederverwaltung_arzten_augenarzt.dart':
          'saveAugenarztTermin',
      'lib/widgets/mitgliederverwaltung_arzten_hno.dart': 'saveHnoTermin',
      'lib/widgets/mitgliederverwaltung_arzten_krankenhaus.dart':
          'saveKrankenhausTermin',
      'lib/widgets/mitgliederverwaltung_arzten_md.dart': 'saveMdTermin',
      'lib/widgets/mitgliederverwaltung_arzten_rheumatologie.dart':
          'saveRheumatologieTermin',
    };

    for (final e in erwartet.entries) {
      test('${e.key.split('/').last} → ${e.value}', () {
        final datei = File(e.key);
        expect(datei.existsSync(), isTrue, reason: 'Datei fehlt: ${e.key}');
        final quelle = datei.readAsStringSync();

        // Genau eine Übergabe, und zwar die richtige.
        final treffer = RegExp(r'speichern: widget\.apiService\.(\w+)')
            .allMatches(quelle)
            .map((m) => m.group(1))
            .toList();
        expect(treffer, [e.value],
            reason: 'Dieser Tab muss mit ${e.value} speichern');
      });
    }
  });
}
