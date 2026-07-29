import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/vorsorge_auto_ticket.dart';

/// Die Vorsorge-Erinnerungen wurden früher als Nebeneffekt von `build()`
/// erzeugt, und das "schon verschickt"-Flag lag im Datensatz *eines* Arztes.
/// Weil derselbe Vorsorge-Tab unter jedem Arzt gerendert wird, verschickte jeder
/// neu geöffnete Arzt-Tab denselben Satz Erinnerungen erneut — Mitglied 18 hatte
/// 10 Arzt-Zeilen und dementsprechend 9-10 Kopien jedes Tickets. Am 26.07.2026
/// wurden 259 solche Duplikate aus der Produktion gelöscht.
///
/// Diese Tests halten die Buchführung auf Mitgliedsebene fest: derselbe Aufruf
/// zweimal darf nur beim ersten Mal etwas verschicken.
void main() {
  final screenings = [
    const VorsorgeScreeningSpec(
      key: 'hautkrebs',
      label: 'Hautkrebs-Screening',
      nurFrauen: false,
      nurMaenner: false,
      abAlter: 35,
      intervallJung: 24,
      intervallAlt: 24,
      altersgrenze: 0,
      beschreibungJung: 'Alle 2 Jahre',
      beschreibungAlt: 'Alle 2 Jahre',
    ),
    const VorsorgeScreeningSpec(
      key: 'hpv',
      label: 'Gebärmutterhalskrebs (HPV/Pap)',
      nurFrauen: true,
      nurMaenner: false,
      abAlter: 20,
      intervallJung: 12,
      intervallAlt: 36,
      altersgrenze: 35,
      beschreibungJung: 'Jährlich Pap-Abstrich',
      beschreibungAlt: 'Alle 3 Jahre Ko-Testung',
    ),
    const VorsorgeScreeningSpec(
      key: 'prostata',
      label: 'Prostata-/Genitaluntersuchung',
      nurFrauen: false,
      nurMaenner: true,
      abAlter: 45,
      intervallJung: 12,
      intervallAlt: 12,
      altersgrenze: 0,
      beschreibungJung: 'Jährlich beim Urologen',
      beschreibungAlt: 'Jährlich beim Urologen',
    ),
  ];

  final heute = DateTime(2026, 7, 26);
  final frau40 = DateTime(1986, 3, 1);

  // Schlafapnoe steht getrennt, weil es das einzige Screening mit Terminkette
  // ist: das mobile Polygraphie-Gerät geht mit nach Hause, wird kontrolliert,
  // zurückgegeben und erst danach wird der Befund besprochen.
  const schlafSlots = [
    VorsorgeTerminSlot(
      key: 'geraet_kontrolle',
      label: 'Gerätekontrolle (mobil)',
      ticketBetreff: 'Schlafapnoe – Gerätekontrolle (mobil)',
      beschreibung: 'Kontrolle des mobilen Geräts.',
    ),
    VorsorgeTerminSlot(
      key: 'gespraech',
      label: 'Gesprächstermin',
      ticketBetreff: 'Schlafapnoe – Gesprächstermin',
      beschreibung: 'Befundbesprechung.',
    ),
  ];
  final schlafScreenings = [
    const VorsorgeScreeningSpec(
      key: 'schlafapnoe',
      label: 'Schlafapnoe-Screening (Polygraphie)',
      nurFrauen: false,
      nurMaenner: false,
      abAlter: 30,
      intervallJung: 24,
      intervallAlt: 24,
      altersgrenze: 0,
      beschreibungJung: 'Ambulante Polygraphie',
      beschreibungAlt: 'Ambulante Polygraphie',
      terminSlots: schlafSlots,
    ),
  ];

  VorsorgePlan planFor({
    Map<String, dynamic> ledger = const {},
    Map<String, String> letztes = const {},
    Set<String> legacyAge = const {},
    Set<String> legacyFrist = const {},
    DateTime? gebDatum,
    String? geschlecht = 'weiblich',
    DateTime? now,
  }) =>
      VorsorgeAutoTicket.planReminders(
        screenings: screenings,
        ledger: ledger,
        geburtsdatum: gebDatum ?? frau40,
        geschlecht: geschlecht,
        now: now ?? heute,
        letztesDatumByKey: letztes,
        legacyAgeSent: legacyAge,
        legacyFristSent: legacyFrist,
      );

  group('Altersanspruch-Erinnerung', () {
    test('leeres Ledger: je berechtigtem Screening genau ein Ticket', () {
      final plan = planFor();
      expect(plan.tickets.map((t) => t.screeningKey), ['hautkrebs', 'hpv']);
      expect(plan.tickets.every((t) => t.kind == VorsorgeReminderKind.age), isTrue);
      // prostata ist nurMaenner, darf für eine Frau nicht auftauchen
      expect(plan.tickets.any((t) => t.screeningKey == 'prostata'), isFalse);
    });

    test('zweiter Arzt-Tab desselben Mitglieds verschickt nichts mehr', () {
      final erster = planFor();
      final ledger = erster.ledger;
      for (final t in erster.tickets) {
        VorsorgeAutoTicket.markSent(ledger, t);
      }

      // Genau das war der Fehler: derselbe Vorsorge-Tab, anderer Arzt-Datensatz.
      final zweiter = planFor(ledger: ledger);
      expect(zweiter.tickets, isEmpty);
      expect(zweiter.ledgerChanged, isFalse);
    });

    test('noch nicht berechtigt -> kein Ticket', () {
      final plan = planFor(gebDatum: DateTime(2016, 1, 1));
      expect(plan.tickets, isEmpty);
    });

    test('ohne Geburtsdatum wird nichts verschickt', () {
      final plan = VorsorgeAutoTicket.planReminders(
        screenings: screenings,
        ledger: const {},
        geburtsdatum: null,
        geschlecht: 'weiblich',
        now: heute,
      );
      expect(plan.tickets, isEmpty);
      expect(plan.ledgerChanged, isFalse);
    });

    test('mit erfasstem letztem Datum entfällt die Anspruchs-Erinnerung', () {
      final plan = planFor(letztes: {'hautkrebs': '2026-07-01'});
      expect(plan.tickets.any((t) => t.screeningKey == 'hautkrebs'), isFalse);
    });
  });

  group('Frist-Erinnerung', () {
    test('fällig in unter einem Monat -> ein Ticket für dieses Fälligkeitsdatum', () {
      // + 24 Monate = 2026-08-10, Erinnerung ab 2026-07-10, heute ist der 26.
      final plan = planFor(letztes: {'hautkrebs': '2024-08-10'});
      final t = plan.tickets.singleWhere((t) => t.screeningKey == 'hautkrebs');
      expect(t.kind, VorsorgeReminderKind.frist);
      expect(t.fristDueKey, '2026-08-10');
      expect(t.priority, 'medium');
    });

    test('überfällig -> hohe Priorität', () {
      final plan = planFor(letztes: {'hautkrebs': '2024-01-10'});
      final t = plan.tickets.singleWhere((t) => t.screeningKey == 'hautkrebs');
      expect(t.priority, 'high');
    });

    test('noch weit hin -> kein Ticket', () {
      final plan = planFor(letztes: {'hautkrebs': '2026-06-01'});
      expect(plan.tickets.any((t) => t.screeningKey == 'hautkrebs'), isFalse);
    });

    test('dasselbe Fälligkeitsdatum wird nicht zweimal verschickt', () {
      final erster = planFor(letztes: {'hautkrebs': '2024-08-10'});
      final ledger = erster.ledger;
      for (final t in erster.tickets) {
        VorsorgeAutoTicket.markSent(ledger, t);
      }
      final zweiter = planFor(ledger: ledger, letztes: {'hautkrebs': '2024-08-10'});
      expect(zweiter.tickets.any((t) => t.screeningKey == 'hautkrebs'), isFalse);
    });

    test('neues Fälligkeitsdatum nach neuer Untersuchung -> wieder erinnern', () {
      final erster = planFor(letztes: {'hautkrebs': '2024-08-10'});
      final ledger = erster.ledger;
      for (final t in erster.tickets) {
        VorsorgeAutoTicket.markSent(ledger, t);
      }
      final spaeter = planFor(
        ledger: ledger,
        letztes: {'hautkrebs': '2026-08-20'},
        now: DateTime(2028, 8, 1),
      );
      final t = spaeter.tickets.singleWhere((t) => t.screeningKey == 'hautkrebs');
      expect(t.fristDueKey, '2028-08-20');
    });

    test('Altersgrenze schaltet auf das lange Intervall um', () {
      // 40 Jahre alt, altersgrenze 35 => intervallAlt 36 statt 12 Monate.
      final plan = planFor(letztes: {'hpv': '2025-01-10'});
      expect(plan.tickets.any((t) => t.screeningKey == 'hpv'), isFalse,
          reason: 'mit 36 Monaten Intervall ist erst 2028 wieder etwas fällig');
    });
  });

  group('Manuell gewählte nächste Kontrolle', () {
    VorsorgePlan schlafPlan({
      Map<String, dynamic> ledger = const {},
      Map<String, String> letztes = const {},
      Map<String, String> naechster = const {},
      Map<String, Map<String, String>> termine = const {},
      DateTime? now,
    }) =>
        VorsorgeAutoTicket.planReminders(
          screenings: schlafScreenings,
          ledger: ledger,
          geburtsdatum: frau40,
          geschlecht: 'weiblich',
          now: now ?? heute,
          letztesDatumByKey: letztes,
          naechsterTerminByKey: naechster,
          terminDatenByKey: termine,
        );

    test('schlägt das Katalog-Intervall: Kontrolle in 6 statt 24 Monaten', () {
      // Katalog wäre 2028-06-01; gewählt ist 2026-08-10, also in unter einem
      // Monat -> die Erinnerung geht jetzt raus, nicht in zwei Jahren.
      final plan = schlafPlan(
        letztes: {'schlafapnoe': '2026-06-01'},
        naechster: {'schlafapnoe': '2026-08-10'},
      );
      final t = plan.tickets.singleWhere((t) => t.kind == VorsorgeReminderKind.frist);
      expect(t.fristDueKey, '2026-08-10');
    });

    test('greift auch ohne letztes Datum', () {
      final plan = schlafPlan(naechster: {'schlafapnoe': '2026-08-10'});
      expect(plan.tickets.single.fristDueKey, '2026-08-10');
    });

    test('geplanter Termin unterdrückt die Anspruchs-Erinnerung', () {
      // Ohne Datum käme "Sie haben nun Anspruch" — neben einem gebuchten
      // Termin ist das nur Rauschen.
      final ohne = schlafPlan();
      expect(ohne.tickets.single.kind, VorsorgeReminderKind.age);
      final mit = schlafPlan(naechster: {'schlafapnoe': '2027-01-10'});
      expect(mit.tickets.any((t) => t.kind == VorsorgeReminderKind.age), isFalse);
    });

    test('Anspruchs-Erinnerung kehrt zurück, wenn der Termin gelöscht wird', () {
      final mit = schlafPlan(naechster: {'schlafapnoe': '2027-01-10'});
      final wieder = schlafPlan(ledger: mit.ledger);
      expect(wieder.tickets.single.kind, VorsorgeReminderKind.age);
    });

    test('dieselbe Kontrolle wird nicht zweimal erinnert', () {
      final erster = schlafPlan(naechster: {'schlafapnoe': '2026-08-10'});
      final ledger = erster.ledger;
      for (final t in erster.tickets) {
        VorsorgeAutoTicket.markSent(ledger, t);
      }
      final zweiter = schlafPlan(ledger: ledger, naechster: {'schlafapnoe': '2026-08-10'});
      expect(zweiter.tickets, isEmpty);
    });

    test('verschobene Kontrolle -> neues Ticket mit dem Datum im Betreff', () {
      final erster = schlafPlan(naechster: {'schlafapnoe': '2026-08-10'});
      final ledger = erster.ledger;
      for (final t in erster.tickets) {
        VorsorgeAutoTicket.markSent(ledger, t);
      }
      final zweiter = schlafPlan(ledger: ledger, naechster: {'schlafapnoe': '2026-08-20'});
      final t = zweiter.tickets.single;
      expect(t.fristDueKey, '2026-08-20');
      // Das Datum muss im Betreff stehen: die Server-Dedup vergleicht nur den
      // Text, ein offenes Ticket der alten Frist würde das neue sonst schlucken.
      expect(t.subject, contains('20.08.2026'));
      expect(t.subject, isNot(erster.tickets.single.subject));
    });
  });

  group('Terminkette (Gerät / Rückgabe / Gespräch)', () {
    VorsorgePlan schlafPlan({
      Map<String, dynamic> ledger = const {},
      Map<String, Map<String, String>> termine = const {},
      DateTime? now,
    }) =>
        VorsorgeAutoTicket.planReminders(
          screenings: schlafScreenings,
          ledger: ledger,
          geburtsdatum: frau40,
          geschlecht: 'weiblich',
          now: now ?? heute,
          letztesDatumByKey: const {'schlafapnoe': '2026-06-01'},
          terminDatenByKey: termine,
        );

    test('eingetragener Termin -> sofort ein Ticket, nicht erst einen Monat vorher', () {
      final plan = schlafPlan(termine: {
        'schlafapnoe': {'geraet_kontrolle': '2027-03-15'},
      });
      final t = plan.tickets.single;
      expect(t.kind, VorsorgeReminderKind.termin);
      expect(t.terminSlotKey, 'geraet_kontrolle');
      expect(t.terminDatum, '2027-03-15');
      expect(t.scheduledDate, '2027-03-15');
      expect(t.subject, 'Schlafapnoe – Gerätekontrolle (mobil) am 15.03.2027');
    });

    test('mehrere Slots -> je Slot ein eigenes Ticket', () {
      final plan = schlafPlan(termine: {
        'schlafapnoe': {'geraet_kontrolle': '2027-03-15', 'gespraech': '2027-04-02'},
      });
      expect(plan.tickets.map((t) => t.terminSlotKey), ['geraet_kontrolle', 'gespraech']);
    });

    test('derselbe Termin erzeugt kein zweites Ticket', () {
      final termine = {
        'schlafapnoe': {'geraet_kontrolle': '2027-03-15'},
      };
      final erster = schlafPlan(termine: termine);
      final ledger = erster.ledger;
      for (final t in erster.tickets) {
        VorsorgeAutoTicket.markSent(ledger, t);
      }
      expect(schlafPlan(ledger: ledger, termine: termine).tickets, isEmpty);
    });

    test('verschobener Termin -> genau ein neues Ticket', () {
      final erster = schlafPlan(termine: {
        'schlafapnoe': {'geraet_kontrolle': '2027-03-15'},
      });
      final ledger = erster.ledger;
      for (final t in erster.tickets) {
        VorsorgeAutoTicket.markSent(ledger, t);
      }
      final zweiter = schlafPlan(ledger: ledger, termine: {
        'schlafapnoe': {'geraet_kontrolle': '2027-03-22'},
      });
      expect(zweiter.tickets.single.terminDatum, '2027-03-22');
      expect(zweiter.tickets.single.subject, contains('22.03.2027'));
    });

    test('gelöschter Termin räumt das Ledger, dasselbe Datum zählt danach neu', () {
      final erster = schlafPlan(termine: {
        'schlafapnoe': {'geraet_kontrolle': '2027-03-15'},
      });
      final ledger = erster.ledger;
      for (final t in erster.tickets) {
        VorsorgeAutoTicket.markSent(ledger, t);
      }
      final geloescht = schlafPlan(ledger: ledger, termine: {
        'schlafapnoe': {'geraet_kontrolle': ''},
      });
      expect(geloescht.tickets, isEmpty);
      expect(geloescht.ledgerChanged, isTrue);
      final erneut = schlafPlan(ledger: geloescht.ledger, termine: {
        'schlafapnoe': {'geraet_kontrolle': '2027-03-15'},
      });
      expect(erneut.tickets.single.terminDatum, '2027-03-15');
    });

    test('ohne Termine passiert nichts', () {
      expect(schlafPlan().tickets, isEmpty);
    });
  });

  group('Migration von den alten Arzt-Flags', () {
    test('altes age-Flag wird übernommen statt erneut verschickt', () {
      final plan = planFor(legacyAge: {'hautkrebs', 'hpv'});
      expect(plan.tickets, isEmpty);
      expect(plan.ledgerChanged, isTrue, reason: 'die Übernahme muss gespeichert werden');
      expect((plan.ledger['age_sent'] as Map)['hautkrebs'], isTrue);
      expect((plan.ledger['age_sent'] as Map)['hpv'], isTrue);
    });

    test('altes Frist-Flag wird auf das aktuelle Fälligkeitsdatum übernommen', () {
      final plan = planFor(
        letztes: {'hautkrebs': '2024-08-10'},
        legacyFrist: {'hautkrebs'},
      );
      expect(plan.tickets.any((t) => t.screeningKey == 'hautkrebs'), isFalse);
      expect((plan.ledger['frist_sent'] as Map)['hautkrebs'], '2026-08-10');
      expect(plan.ledgerChanged, isTrue);
    });

    test('Übernahme passiert nur einmal', () {
      final erster = planFor(legacyAge: {'hautkrebs', 'hpv'});
      final zweiter = planFor(ledger: erster.ledger, legacyAge: {'hautkrebs', 'hpv'});
      expect(zweiter.ledgerChanged, isFalse);
      expect(zweiter.tickets, isEmpty);
    });
  });

  group('Geschlechtsfilter', () {
    test('Mann bekommt Prostata, nicht HPV', () {
      final plan = planFor(gebDatum: DateTime(1976, 3, 1), geschlecht: 'männlich');
      final keys = plan.tickets.map((t) => t.screeningKey).toSet();
      expect(keys, contains('prostata'));
      expect(keys, isNot(contains('hpv')));
    });

    test('ohne Geschlechtsangabe entfallen die geschlechtsgebundenen Screenings', () {
      final plan = planFor(geschlecht: null);
      final keys = plan.tickets.map((t) => t.screeningKey).toSet();
      expect(keys, {'hautkrebs'});
    });
  });

  group('Eingangsdaten werden nicht verändert', () {
    test('planReminders lässt das übergebene Ledger unangetastet', () {
      final original = <String, dynamic>{
        'age_sent': <String, dynamic>{'hautkrebs': true},
      };
      final plan = planFor(ledger: original);
      VorsorgeAutoTicket.markSent(plan.ledger, plan.tickets.first);
      expect((original['age_sent'] as Map).containsKey('hpv'), isFalse);
    });
  });
}
